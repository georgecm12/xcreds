//
//  WebView.swift
//  xCreds
//
//  Created by Timothy Perfitt on 4/5/22.
//

import Foundation
import Cocoa
import WebKit
import OIDCLite
import Network
class LoginWebViewController: WebViewController {
    let uiLog = "uiLog"
    let monitor = NWPathMonitor()
    var delegate: XCredsMechanismProtocol?
    var resolutionObserver:Any?
    var loginProgressWindowController:LoginProgressWindowController?
    @IBOutlet weak var backgroundImageView: NSImageView!

    override func windowDidLoad() {
        super.windowDidLoad()
        
        resolutionObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { notification in
            TCSLogWithMark("Resolution changed. Resetting size")
            self.setupLoginWindowAppearance()

        }
        TCSLogWithMark("loading webview for login")
        setupLoginWindowAppearance()

        TCSLogWithMark("loading page")

        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {

                TCSLogWithMark("network changed")
                DispatchQueue.main.async {

                    self.loadPage()
                }

            } else {
                TCSLogWithMark("No connection.")
            }

            print(path.isExpensive)
        }
        let queue = DispatchQueue(label: "Monitor")
        monitor.start(queue: queue)

        loadPage()
    }
    fileprivate func setupLoginWindowAppearance() {
        DispatchQueue.main.async {
//            TCSLogWithMark("webview frame is \(self.webView.frame.debugDescription)")


            TCSLogWithMark("setting up window...")

            self.window?.level = .popUpMenu
            self.window?.orderFrontRegardless()

            self.window?.backgroundColor = NSColor.blue

            self.window?.titlebarAppearsTransparent = true
            
            self.window?.isMovable = false
            self.window?.canBecomeVisibleWithoutLogin = true

            let screenRect = NSScreen.screens[0].frame
            let screenWidth = screenRect.width
            let screenHeight = screenRect.height
            var loginWindowWidth = screenWidth //start with full size
            var loginWindowHeight = screenHeight //start with full size

            //if prefs define smaller, then resize window
            TCSLogWithMark("checking for custom height and width")
            if UserDefaults.standard.object(forKey: PrefKeys.loginWindowWidth.rawValue) != nil  {
                let val = CGFloat(UserDefaults.standard.float(forKey: PrefKeys.loginWindowWidth.rawValue))
                if val > 100 {
                    TCSLogWithMark("setting loginWindowWidth to \(val)")
                    loginWindowWidth = val
                }
            }
            if UserDefaults.standard.object(forKey: PrefKeys.loginWindowHeight.rawValue) != nil {
                let val = CGFloat(UserDefaults.standard.float(forKey: PrefKeys.loginWindowHeight.rawValue))
                if val > 100 {
                    TCSLogWithMark("setting loginWindowHeight to \(val)")
                    loginWindowHeight = val
                }
            }

            self.window?.setFrame(screenRect, display: true, animate: false)

            TCSLogWithMark("webview is \(self.webView.debugDescription)")
//            TCSLogWithMark("webview frame is \(self.webView.frame.debugDescription)")

            self.webView.frame=NSMakeRect((screenWidth-CGFloat(loginWindowWidth))/2,(screenHeight-CGFloat(loginWindowHeight))/2, CGFloat(loginWindowWidth), CGFloat(loginWindowHeight))

//            BackgroundImage
            if let imagePathURL = UserDefaults.standard.string(forKey: PrefKeys.loginWindowBackgroundImageURL.rawValue), let image = NSImage.imageFromPathOrURL(pathURLString: imagePathURL){
                TCSLogWithMark("background path is \(imagePathURL)")
                image.size=screenRect.size
                self.backgroundImageView.image=image
                self.backgroundImageView.imageScaling = .scaleProportionallyUpOrDown

                self.backgroundImageView.frame=NSMakeRect(screenRect.origin.x, screenRect.origin.y, screenRect.size.width, screenRect.size.height-100)


            }
            else {
                let allBundles = Bundle.allBundles
                for currentBundle in allBundles {
                    TCSLogWithMark(currentBundle.bundlePath)
                    if currentBundle.bundlePath.contains("XCreds"), let imagePath = currentBundle.path(forResource: "DefaultBackground", ofType: "png") {
                        TCSLogWithMark()

                        let image = NSImage.init(byReferencingFile: imagePath)

                        if let image = image {
                            TCSLogWithMark()
                            image.size=screenRect.size
                            self.backgroundImageView.image=image
                            self.backgroundImageView.imageScaling = .scaleProportionallyUpOrDown
                            self.backgroundImageView.frame=NSMakeRect(screenRect.origin.x, screenRect.origin.y, screenRect.size.width, screenRect.size.height-100)
                        }


                        break

                    }
                }
            }

        }
//            self.window?.setFrame(NSMakeRect((screenWidth-CGFloat(width))/2,(screenHeight-CGFloat(height))/2, CGFloat(width), CGFloat(height)), display: true, animate: false)
//        }
//
    }

    @objc override var windowNibName: NSNib.Name {
        return NSNib.Name("LoginWebView")
    }
    func loginTransition() {
//
//        let screenRect = NSScreen.screens[0].frame
//        let progressIndicator=NSProgressIndicator.init(frame: NSMakeRect(screenRect.width/2-16  , 3*screenRect.height/4-16,32, 32))
//        progressIndicator.style = .spinning
//        progressIndicator.startAnimation(self)
//        webView.addSubview(progressIndicator)

//        loginProgressWindowController = LoginProgressWindowController.init(windowNibName: NSNib.Name("LoginProgressWindowController"))
//        if let loginProgressWindowController = loginProgressWindowController {
//            loginProgressWindowController.window?.makeKeyAndOrderFront(self)
//
//
//        }
        self.window?.close()


//        NSAnimationContext.runAnimationGroup({ (context) in
//            context.duration = 1.0
//            context.allowsImplicitAnimation = true
//            self.window?.alphaValue = 0.0
//        }, completionHandler: {
//            self.window?.close()
//        })
    }

    override func tokensUpdated(tokens: Creds) {
//if we have tokens, that means that authentication was successful.
//we have to check the password here so we can prompt.

        guard let delegate = delegate else {
            TCSLogWithMark("invalid delegate")
            return
        }
        var username:String
        let defaultsUsername = UserDefaults.standard.string(forKey: PrefKeys.username.rawValue)

        guard let idToken = tokens.idToken else {
            TCSLogWithMark("invalid idToken")

            delegate.denyLogin()
            return
        }

        let array = idToken.components(separatedBy: ".")

        if array.count != 3 {
            TCSLogWithMark("idToken is invalid")
            delegate.denyLogin()
        }
        let body = array[1]
        TCSLogWithMark("base64 encoded IDToken: \(body)");
        guard let data = base64UrlDecode(value:body ) else {
            TCSLogWithMark("error decoding id token base64")
            delegate.denyLogin()
            return
        }
        let decoder = JSONDecoder()
        var idTokenObject:IDToken
        do {
            idTokenObject = try decoder.decode(IDToken.self, from: data)

        }
        catch {
            TCSLogWithMark("error decoding idtoken::")
            TCSLogWithMark("Token:\(body)")
            delegate.denyLogin()
            return

        }

        let idTokenInfo = jwtDecode(value: idToken)  //dictionary for mappnigs

        // username static map
        if let defaultsUsername = defaultsUsername {
            username = defaultsUsername
        }
        else if let idTokenInfo = idTokenInfo, let mapKey = UserDefaults.standard.object(forKey: "map_username")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
//we have a mapping for username, so use that.

            username = mapValue
            TCSLogWithMark("mapped username found: \(username)")

        }
        else {
            var emailString:String

            if let email = idTokenObject.email  {
                emailString=email.lowercased()
            }
            else if let uniqueName=idTokenObject.unique_name {
                emailString=uniqueName
            }

            else {
                TCSLogWithMark("no username found. Using sub.")
                emailString=idTokenObject.sub
            }
            guard let tUsername = emailString.components(separatedBy: "@").first?.lowercased() else {
                TCSLogWithMark("email address invalid")
                delegate.denyLogin()
                return

            }

            TCSLogWithMark("username found: \(tUsername)")
            username = tUsername
        }

        //full name
        TCSLogWithMark("checking map_fullname")

        if let idTokenInfo = idTokenInfo, let mapKey = UserDefaults.standard.object(forKey: "map_fullname")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
//we have a mapping so use that.
            TCSLogWithMark("full name mapped to: \(mapKey)")

            delegate.setHint(type: .fullName, hint: "\(mapValue)")

        }

        else if let firstName = idTokenObject.given_name, let lastName = idTokenObject.family_name {
            TCSLogWithMark("firstName: \(firstName)")
            TCSLogWithMark("lastName: \(lastName)")
            delegate.setHint(type: .fullName, hint: "\(firstName) \(lastName)")

        }

        //first name
        if let idTokenInfo = idTokenInfo, let mapKey = UserDefaults.standard.object(forKey: "map_firstname")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
//we have a mapping for username, so use that.
            TCSLogWithMark("first name mapped to: \(mapKey)")

            delegate.setHint(type: .firstName, hint:mapValue)
        }

       else if let firstName = idTokenObject.given_name {
           TCSLogWithMark("firstName from token: \(firstName)")

            delegate.setHint(type: .firstName, hint:firstName)

        }
        //last name
        TCSLogWithMark("checking map_lastname")

        if let idTokenInfo = idTokenInfo, let mapKey = UserDefaults.standard.object(forKey: "map_lastname")  as? String, mapKey.count>0, let mapValue = idTokenInfo[mapKey] as? String {
//we have a mapping for lastName, so use that.
            TCSLogWithMark("last name mapped to: \(mapKey)")

            delegate.setHint(type: .lastName, hint:mapValue)
        }

        else if let lastName = idTokenObject.family_name {
            TCSLogWithMark("lastName from token: \(lastName)")

            delegate.setHint(type: .lastName, hint:lastName)

        }
        TCSLogWithMark("checking local password for username:\(username) and password length: \(tokens.password.count)");

        let isValidPassword =  try? PasswordUtils.isLocalPasswordValid(userName: username, userPass: tokens.password)

        if isValidPassword==false{

            if let keychainReset = getManagedPreference(key: .KeychainReset) as? Bool, keychainReset==true{
                TCSLogWithMark("local password is different from cloud password but keychain reset pref is set. Skipping prompting so later we can create a new keychain.")

                if (getManagedPreference(key: .PasswordOverwriteSilent) as? Bool ?? false) {
                    // set the hint and return complete
                    os_log("Setting password to be overwritten.", log: uiLog, type: .default)
                    delegate.setHint(type: .passwordOverwrite, hint: true)
                    os_log("Hint set", log: uiLog, type: .debug)
                }
            }
            else {
                TCSLogWithMark("local password is different from cloud password. Prompting for local password...")

                let passwordWindowController = LoginPasswordWindowController.init(windowNibName: NSNib.Name("LoginPasswordWindowController"))

                if passwordWindowController.window==nil {
                    TCSLogWithMark("no passwordWindowController window")
                    delegate.denyLogin()
                    return
                }
                passwordWindowController.window?.canBecomeVisibleWithoutLogin=true
                passwordWindowController.window?.isMovable = false
                passwordWindowController.window?.canBecomeVisibleWithoutLogin = true
                passwordWindowController.window?.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
                while (true){
                    //                NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async{
                        TCSLogWithMark("resetting level")
                        passwordWindowController.window?.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
                    }
                    TCSLogWithMark("showing modal")

                    let response = NSApp.runModal(for: passwordWindowController.window!)

                    TCSLogWithMark("modal done")
                    if response == .cancel {
                        break
                    }
                    let resetKeychain = passwordWindowController.resetKeychain

                    if resetKeychain == true {
                        os_log("Setting password to be overwritten.", log: uiLog, type: .default)
                        delegate.setHint(type: .passwordOverwrite, hint: true)
                        os_log("Hint set", log: uiLog, type: .debug)
                        passwordWindowController.window?.close()
                        break

                    }
                    else {
                        let localPassword = passwordWindowController.password
                        guard let localPassword = localPassword else {
                            continue
                        }
                        let isValidPassword =  try? PasswordUtils.isLocalPasswordValid(userName: username, userPass: localPassword)

                        if isValidPassword==true {
                            let localUser = try? PasswordUtils.getLocalRecord(username)
                            guard let localUser = localUser else {
                                TCSLogWithMark("invalid local user")
                                delegate.denyLogin()
                                return
                            }
                            do {
                                try localUser.changePassword(localPassword, toPassword: tokens.password)
                            }
                            catch {
                                TCSLogWithMark("Error setting local password to cloud password")
                                delegate.denyLogin()
                                return
                            }
                            TCSLogWithMark("setting original password to use to unlock keychain later")
                            delegate.setHint(type: .migratePass, hint: localPassword)
                            passwordWindowController.window?.close()
                            break

                        }
                        else{
                            passwordWindowController.window?.shake(self)
                        }
                    }
                }
            }

        }
        TCSLogWithMark("passing username:\(username), password, and tokens")
        TCSLogWithMark("setting kAuthorizationEnvironmentUsername")

        delegate.setContextString(type: kAuthorizationEnvironmentUsername, value: username)
        TCSLogWithMark("setting kAuthorizationEnvironmentPassword")

        delegate.setContextString(type: kAuthorizationEnvironmentPassword, value: tokens.password)
        TCSLogWithMark("setting username")

        delegate.setHint(type: .user, hint: username)
        TCSLogWithMark("setting tokens.password")

        delegate.setHint(type: .pass, hint: tokens.password)
//        setHint(type: .noMADFirst, hint: user.firstName)
//        setHint(type: .noMADLast, hint: user.lastName)
//        setHint(type: .noMADDomain, hint: domainName)
//        setHint(type: .noMADGroups, hint: user.groups)
//        delegate.setHint(type: .fullName, hint: idTokenObject.unique_name ?? username)
//        delegate.setHint(type: .firstName, hint: idTokenObject.given_name ?? "")
//        delegate.setHint(type: .lastName, hint: idTokenObject.family_name ?? "")

        TCSLogWithMark("setting tokens")
        delegate.setHint(type: .tokens, hint: [tokens.idToken ?? "",tokens.refreshToken ?? "",tokens.accessToken ?? ""])
        if let resolutionObserver = resolutionObserver {
            NotificationCenter.default.removeObserver(resolutionObserver)
        }

        RunLoop.main.perform {
            self.loginTransition()
        }
        delegate.allowLogin()


    }
}


