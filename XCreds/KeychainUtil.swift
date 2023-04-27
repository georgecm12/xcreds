//
//  KeychainUtil.swift
//  NoMAD
//
//  Created by Joel Rennich on 8/7/16.
//  Copyright © 2016 Trusource Labs. All rights reserved.
//

// class to manage all keychain interaction

enum KeychainError: Error {
    case notConnected
    case notLoggedIn
    case noPasswordExpirationTime
    case ldapServerLookup
    case ldapNamingContext
    case ldapServerPasswordExpiration
    case ldapConnectionError
    case userPasswordSetDate
    case userHome
    case noStoredPassword
    case storedPasswordWrong
}



import Foundation
import Security

struct certDates {
    var serial : String
    var expireDate : Date
}

class KeychainUtil {

    var myErr: OSStatus
    let serviceName = "xcreds"
    var passLength: UInt32 = 0
    var passPtr: UnsafeMutableRawPointer? = nil

    var myKeychainItem: SecKeychainItem?

    init() {
        myErr = 0
    }

    // find if there is an existing account password and return it or throw

    func findPassword(_ name: String) throws -> String {

        TCSLogWithMark("Finding \(name) in keychain")
        myErr = SecKeychainFindGenericPassword(nil, UInt32(serviceName.count), serviceName, UInt32(name.count), name, &passLength, &passPtr, &myKeychainItem)

        if myErr == OSStatus(errSecSuccess) {
            let password = NSString(bytes: passPtr!, length: Int(passLength), encoding: String.Encoding.utf8.rawValue)
            if password != "" {
                TCSLogWithMark("\(name) found in keychain")
            }
            return password as? String ?? ""
        } else {
            TCSLogWithMark("Password not found in keychain")
            throw KeychainError.noStoredPassword
        }
    }

    // set the password

    func setPassword(_ name: String, pass: String) -> OSStatus {

        myErr = SecKeychainAddGenericPassword(nil, UInt32(serviceName.count), serviceName, UInt32(name.count), name, UInt32(pass.count), pass, &myKeychainItem)

        return myErr
    }

    func updatePassword(_ name: String, pass: String, shouldUpdateACL:Bool=false, keychainPassword:String?=nil ) -> Bool {
        if (try? findPassword(name)) != nil {
            TCSLogWithMark("Deleting password")
            let _ = deletePassword()
        }
        TCSLogWithMark("setting new password")

        myErr = setPassword(name, pass: pass)
        if myErr != OSStatus(errSecSuccess) {
            TCSLogWithMark("setting new password FAILURE")
            return false
        }
        TCSLogWithMark("setting new password success")

        if shouldUpdateACL==true {
            if let keychainPassword = keychainPassword {
                TCSLogWithMark("Updating ACL for \(name)")

                updateACL(password:keychainPassword)
            }
            else {
                TCSLogWithMark("ERROR Updating ACL")

                return false
            }
            
        }
        return true
    }

    // delete the password from the keychain

    func deletePassword() -> OSStatus {
        myErr = SecKeychainItemDelete(myKeychainItem!)
        return myErr
    }

    // convience functions

    func findAndDelete(_ name: String) -> Bool {
        do {
            try findPassword(name)
        } catch{
            return false
        }
        if ( deletePassword() == 0 ) {
            return true
        } else {
            return false
        }
    }
    func updateACL(password:String){
        var myACLs : CFArray? = nil
        var itemAccess: SecAccess? = nil

        guard let keychainItem = myKeychainItem else {
            TCSLogWithMark("Keychain item not found")
            return
        }
        var err = SecKeychainItemCopyAccess(keychainItem, &itemAccess)

        guard let itemAccess = itemAccess else {
            TCSLogWithMark("item access invalid")
            return
        }

        SecAccessCopyACLList(itemAccess, &myACLs)

        var appList: CFArray? = nil
        var desc: CFString? = nil

        var prompt = SecKeychainPromptSelector()
        var secApps = [ SecTrustedApplication ]()

        var trust : SecTrustedApplication? = nil
        if FileManager.default.fileExists(atPath: "/Applications/XCreds.app", isDirectory: nil) {
            err = SecTrustedApplicationCreateFromPath("/Applications/XCreds.app", &trust)
            if err == 0 {
                secApps.append(trust!)
            }
        }
        if FileManager.default.fileExists(atPath: "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.x86_64.xpc", isDirectory: nil) {
            err = SecTrustedApplicationCreateFromPath("/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.x86_64.xpc", &trust)
            if err == 0 {
                secApps.append(trust!)
            }
        }
        if FileManager.default.fileExists(atPath: "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.arm64.xpc", isDirectory: nil) {
            err = SecTrustedApplicationCreateFromPath("/System/Library/Frameworks/Security.framework/Versions/A/MachServices/authorizationhost.bundle/Contents/XPCServices/authorizationhosthelper.arm64.xpc", &trust)
            if err == 0 {
                secApps.append(trust!)
            }
        }

        for acl in myACLs as! Array<SecACL> {
            SecACLCopyContents(acl, &appList, &desc, &prompt)
            let authArray = SecACLCopyAuthorizations(acl)

            if (authArray as! [String]).contains("ACLAuthorizationDecrypt") {

                TCSLogWithMark("Found AUTHORIZATION_CHANGE_ACL.")

                SecACLSetContents(acl, secApps as CFArray, "" as CFString, prompt)
                continue
            }

            if !(authArray as! [String]).contains("ACLAuthorizationPartitionID") {
                continue
            }

            TCSLogWithMark("Found ACLAuthorizationPartitionID.")

            // pull in the description that's really a functional plist <sigh>
            let rawData = Data.init(fromHexEncodedString: desc! as String)
            var format: PropertyListSerialization.PropertyListFormat = .xml

            var propertyListObject = [ String: [String]]()

            do {
                propertyListObject = try PropertyListSerialization.propertyList(from: rawData!, options: [], format: &format) as! [ String: [String]]
            } catch {
                TCSLogWithMark("No teamid in ACLAuthorizationPartitionID.")
            }
            let teamIds = [ "apple:", "teamid:5ZZJPRV475" ]

            propertyListObject["Partitions"] = teamIds

            // now serialize it back into a plist

            let xmlObject = try? PropertyListSerialization.data(fromPropertyList: propertyListObject as Any, format: format, options: 0)

            // now that all ACLs has been adjusted, we can update the item

            err = SecACLSetContents(acl, appList, xmlObject!.hexEncodedString() as CFString, prompt)

            // smack it again to set the ACL
            err = SecKeychainItemSetAccessWithPassword(keychainItem, itemAccess, UInt32(password.count), password)
        }
    }
//
//    // return the last expiration date for any certs that match the domain and user
//
//    func findCertExpiration(_ identifier: String, defaultNamingContext: String) -> Date? {
//
//        var matchingCerts = [certDates]()
//        var myCert: SecCertificate? = nil
//        var searchReturn: AnyObject? = nil
//        var lastExpire = Date.distantPast
//
//        // create a search dictionary to find Identitys with Private Keys and returning all matches
//
//        /*
//         @constant kSecMatchIssuers Specifies a dictionary key whose value is a
//         CFArray of X.500 names (of type CFDataRef). If provided, returned
//         certificates or identities will be limited to those whose
//         certificate chain contains one of the issuers provided in this list.
//         */
//
//        // build our search dictionary
//
//        let identitySearchDict: [String:AnyObject] = [
//            kSecClass as String: kSecClassIdentity,
//            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate as String as String as AnyObject,
//
//            // this matches e-mail address
//            //kSecMatchEmailAddressIfPresent as String : identifier as CFString,
//
//            // this matches Common Name
//            //kSecMatchSubjectContains as String : identifier as CFString,
//
//            kSecReturnRef as String: true as AnyObject,
//            kSecMatchLimit as String : kSecMatchLimitAll as AnyObject
//        ]
//
//        myErr = 0
//
//
//        // look for all matches
//
//        myErr = SecItemCopyMatching(identitySearchDict as CFDictionary, &searchReturn)
//
//        if myErr != 0 {
//            return nil
//        }
//
//        let foundCerts = searchReturn as! CFArray as Array
//
//        if foundCerts.count == 0 {
//            return nil
//        }
//
//        for cert in foundCerts {
//
//            myErr = SecIdentityCopyCertificate(cert as! SecIdentity, &myCert)
//
//            if myErr != 0 {
//                return nil
//            }
//
//                    // get the full OID set for the cert
//
//                    let myOIDs : NSDictionary = SecCertificateCopyValues(myCert!, nil, nil)!
//
//            // look at the NT Principal name
//
//            if myOIDs["2.5.29.17"] != nil {
//                let SAN = myOIDs["2.5.29.17"] as! NSDictionary
//                let SANValues = SAN["value"]! as! NSArray
//                for values in SANValues {
//                    let value = values as! NSDictionary
//                    if String(_cocoaString: value["label"]! as AnyObject) == "1.3.6.1.4.1.311.20.2.3" {
//                        if let myNTPrincipal = value["value"] {
//                            // we have an NT Principal, let's see if it's Kerberos Principal we're looking for
//                            myLogger.logit(.debug, message: "Certificate NT Principal: " + String(describing: myNTPrincipal) )
//                            if String(describing: myNTPrincipal) == identifier {
//myLogger.logit(.debug, message: "Found cert match")
//
//
//                                                // we have a match now gather the expire date and the serial
//
//                                                let expireOID : NSDictionary = myOIDs["2.5.29.24"]! as! NSDictionary
//                                                let expireDate = expireOID["value"]! as! Date
//
//                                                // this finds the serial
//
//                                                let serialDict : NSDictionary = myOIDs["2.16.840.1.113741.2.1.1.1.3"]! as! NSDictionary
//                                                let serial = serialDict["value"]! as! String
//
//                                                // pack the data up into a certDate
//
//                                                let certificate = certDates( serial: serial, expireDate: expireDate)
//
//                                                if lastExpire.timeIntervalSinceNow < expireDate.timeIntervalSinceNow {
//                                                    lastExpire = expireDate
//                                                }
//
//                                                // append to the list
//
//                                                matchingCerts.append(certificate)
//
//                            } else {
//myLogger.logit(.debug, message: "Certificate doesn't match current user principal.")
//                            }
//                        }
//
//                    }
//                }
//            }
//
//            }
//        myLogger.logit(.debug, message: "Found " + String(matchingCerts.count) + " certificates.")
//        myLogger.logit(.debug, message: "Found certificates: " + String(describing: matchingCerts) )
//        return lastExpire
//    }
}
