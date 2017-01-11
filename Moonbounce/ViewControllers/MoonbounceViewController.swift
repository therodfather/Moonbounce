//
//  MoonbounceViewController.swift
//  Moonbounce
//
//  Created by Adelita Schule on 10/24/16.
//  Copyright © 2016 operatorfoundation.org. All rights reserved.
//

import Cocoa

class MoonbounceViewController: NSViewController
{
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var advancedModeButton: NSButton!
    @IBOutlet weak var toggleConnectionButton: CustomButton!
    @IBOutlet weak var backgroundImageView: NSImageView!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var laserImageView: NSImageView!
    @IBOutlet weak var laserLeadingConstraint: NSLayoutConstraint!

    dynamic var runningScript = false
    static var shiftedOpenVpnController = ShapeshiftedOpenVpnController()
    static var terraformController = TerraformController()
    
    //Advanced Mode Outlets
    @IBOutlet weak var advancedModeHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var serverSelectButton: NSPopUpButton!
    @IBOutlet weak var serverProgressBar: NSProgressIndicator!
    @IBOutlet weak var accountTokenBox: NSBox!
    @IBOutlet weak var accountTokenTextField: NSTextField!
    
    //accountTokenBox.hidden is bound to this var
    dynamic var hasDoToken = false
    
    let proximaNARegular = "Proxima Nova Alt Regular"
    let advancedMenuHeight: CGFloat = 150.0
    
    enum ServerName: String
    {
        case defaultServer = "Default Server"
        case userServer = "User Server"
        case importedServer = "Imported Server"
    }
        
    //MARK: View Life Cycle
    
    override func viewDidLoad()
    {
        super.viewDidLoad()

        //Listen for Bash output from Helper App
        CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), nil,
        {
            (_, observer, notificationName, object, userInfo) in
            
            if let observer = observer, let userInfo = userInfo
            {
                //Extract pointer to 'self' from void pointer
                //let mySelf = Unmanaged<MoonbounceViewController>.fromOpaque(observer).takeUnretainedValue()
                print("\nOutput from Helper App: \(userInfo)\n")
            }
            
        }, kOutputTextNotification, nil, CFNotificationSuspensionBehavior.deliverImmediately)
        //NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: kOutputTextNotification), object: nil, queue: nil, using: showProcessOutputInTextView)
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: kConnectionStatusNotification), object: nil, queue: nil, using: connectionStatusChanged)
        
        updateStatusUI(connected: false, statusDescription: "Not Connected")
        populateServerSelectButton()
    }
    
    override func viewWillAppear()
    {
        super.viewWillAppear()
        
        styleViews()
    }
    
    func connectionStatusChanged(notification: Notification)
    {
        showStatus()
    }
    
    //MARK: Action!
    @IBAction func toggleConnection(_ sender: NSButton)
    {
        switch isConnected.state
        {
            case .start:
                switch isConnected.stage
                {
                case .start:
                    self.connect()
                default:
                    print("Error: Connected state of Start but Stage is \(isConnected.stage)")
                }
            case .trying:
                switch isConnected.stage
                {
                    case .start:
                        //Should Not Happen
                        print("Error: Connected state of Trying but Stage is Start")
                    default:
                        //Terminate Dispatcher Task & Kill OpenVPN & Management
                        disconnect()
                }
            case .success:
                disconnect()
            case .failed:
                connect()
        }
    }
    
    @IBAction func showAdvancedMode(_ sender: AnyObject)
    {
        if advancedModeHeightConstraint.constant > 0
        {
            closeMenu(sender: sender)
        }
        else
        {
            showMenu(sender: sender)
        }
    }
    
    @IBAction func serverSelectionChanged(_ sender: NSPopUpButton)
    {
        if let selectedItemTitle = sender.selectedItem?.title
        {
            setSelectedServer(title: selectedItemTitle)
        }
        else
        {
            print("Unable to understand server selection, we could not get an item title from the popup button.")
        }
    }
    
    @IBAction func addFileClicked(_ sender: CustomButton)
    {
        let openDialog = NSOpenPanel()
        openDialog.title = "Select Your Server Config Directory"
        openDialog.canChooseDirectories = true
        openDialog.canChooseFiles = false
        openDialog.allowsMultipleSelection = false
        //openDialog.allowedFileTypes = ["css","html","pdf","png"]

        if let presentingWindow = self.view.window
        {
            openDialog.beginSheetModal(for: presentingWindow)
            {
                (response) in
                
                guard response == NSFileHandlingPanelOKButton
                    else { return }
                
                let fileManager = FileManager.default
                
                if let chosenPath = openDialog.url?.path
                {
                    let chosenPathFileOrFolderName = fileManager.displayName(atPath: chosenPath)
                    let newDirectoryForFiles = configFilesDirectory.appending("/Imported/\(chosenPathFileOrFolderName)")
                    print("Found Files at: \(chosenPath)")
                    //TODO: Verify and Save Config Files
                    
                    //Verify Files
                    
                    //Save to Correct Directory
                    do
                    {
                        try fileManager.copyItem(atPath: chosenPath, toPath: newDirectoryForFiles)
                    }
                    catch let error
                    {
                        print("Unable to copy config files at: \(chosenPath), to: \(newDirectoryForFiles)\nError: \(error)")
                    }
                }
            }
        }
    }
    
    @IBAction func launchServer(_ sender: NSButton)
    {
        if hasDoToken
        {
            sender.isEnabled = false
            toggleConnectionButton.isEnabled = false
            serverProgressBar.startAnimation(self)
            
            MoonbounceViewController.terraformController.launchTerraformServer
            {
                (launched) in
                
                sender.isEnabled = true
                self.toggleConnectionButton.isEnabled = true
                self.serverProgressBar.stopAnimation(self)
                self.populateServerSelectButton()
                
                print("Launch server task exited.")
            }
        }
        else
        {
            //Show Token Input Field
            //self.accountTokenBox.isHidden = false
        }

    }
    
    @IBAction func killServer(_ sender: NSButton)
    {
        sender.isEnabled = false
        toggleConnectionButton.isEnabled = false
        serverProgressBar.startAnimation(self)
        
        MoonbounceViewController.terraformController.destroyTerraformServer
        {
            (destroyed) in
            
            sender.isEnabled = true
            self.toggleConnectionButton.isEnabled = true
            self.serverProgressBar.stopAnimation(self)
            self.populateServerSelectButton()
            
            print("Destroy server task exited.")
        }
    }
    
    @IBAction func closeTokenWindow(_ sender: NSButton)
    {
        self.accountTokenBox.isHidden = true
    }
    
    @IBAction func accountTokenEntered(_ sender: NSTextField)
    {
        //TODO: Sanity checks for input are needed here
        let newToken = sender.stringValue
        if newToken == ""
        {
            print("User entered an empty string for DO token")
            return
        }
        else
        {
            print("New user token: \(newToken)")
            UserDefaults.standard.set(sender.stringValue, forKey: userTokenKey)
            hasDoToken = true
            //accountTokenBox.isHidden = true
            MoonbounceViewController.terraformController.createVarsFile(token: sender.stringValue)
        }
    }
    
    //MARK: OVPN
    func connect()
    {
        serverSelectButton.isEnabled = false
        runBackgroundAnimation()
        isConnected = ConnectState(state: .start, stage: .start)
        runningScript = true
        
        //Update button name
        self.toggleConnectionButton.title = "Disconnect"

        //TODO: Config File Path Based on User Input
        MoonbounceViewController.shiftedOpenVpnController.start(configFilePath: currentConfigDirectory, completion:
        {
            (didLaunch) in
            
            //Go back to the main thread
            DispatchQueue.main.async(execute:
            {
                //You can safely do UI stuff here
                //Verify that connection was succesful and update accordingly
                self.runningScript = false
                self.serverSelectButton.isEnabled = true
                self.showStatus()
            })
        })
    }
    
    func setSelectedServer(title: String)
    {
        switch title
        {
            case ServerName.defaultServer.rawValue:
                currentConfigDirectory = defaultConfigDirectory
            case ServerName.userServer.rawValue:
                currentConfigDirectory = userConfigDirectory
            case ServerName.importedServer.rawValue:
                currentConfigDirectory = importedConfigDirectory
            default:
                print("User made a server selection that we just don't understand: \(title)")
                return
        }
    
        checkForServerIP()
    }
    
    func checkForServerIP()
    {
        //Get the file that has the server IP
        if currentConfigDirectory != ""
        {
            //TODO: This will need to point to something different based on what config files are being used
            let ipFileDirectory = currentConfigDirectory.appending("/" + ipFileName)
            
            do
            {
                let ip = try String(contentsOfFile: ipFileDirectory, encoding: String.Encoding.ascii)
                currentServerIP = ip
                print("Current Server IP is: \(ip)")
            }
            catch
            {
                print("Unable to locate the server IP at: \(ipFileDirectory).")
            }
        }
    }
    
    func disconnect()
    {
        MoonbounceViewController.shiftedOpenVpnController.stop(completion:
        {
            (stopped) in
            //
        })
        
        self.runningScript = false
    }
    
    func showStatus()
    {
        switch isConnected.state
        {
        case .start:
            switch isConnected.stage
            {
            case .start:
                self.updateStatusUI(connected: false, statusDescription: "Not Connected")
            default:
                print("Error: Connected state of Start but Stage is \(isConnected.stage)")
            }
        case .trying:
            switch isConnected.stage
            {
                case .start:
                    //Should Not Happen
                    print("Error: Connected state of Trying but Stage is Start")
                case .dispatcher:
                    self.updateStatusUI(connected: true, statusDescription: "Starting Dispatcher")
                case .openVpn:
                    self.updateStatusUI(connected: true, statusDescription: "Launching OpenVPN")
                case .management:
                    self.updateStatusUI(connected: true, statusDescription: "Connecting to the Management Server")
                case .statusCodes:
                    self.updateStatusUI(connected: true, statusDescription: "Getting OpenVPN Status")
            }
        case .success:
            switch isConnected.stage
            {
            case .start:
                //Should Not Happen
                print("Error: Connected state of Success but Stage is Start")
            case .dispatcher:
                self.updateStatusUI(connected: true, statusDescription: "Started Dispatcher")
            case .openVpn:
                self.updateStatusUI(connected: true, statusDescription: "Launched OpenVPN")
            case .management:
                self.updateStatusUI(connected: true, statusDescription: "Connected to the Management Server")
            case .statusCodes:
                self.updateStatusUI(connected: true, statusDescription: "Connected")
            }
        case .failed:
            switch isConnected.stage
            {
            case .start:
                //Should Not Happen
                print("Error: Connected state of Failed but Stage is Start")
            case .dispatcher:
                self.updateStatusUI(connected: false, statusDescription: "Failed to start Dispatcher")
            case .openVpn:
                self.updateStatusUI(connected: false, statusDescription: "Failed to launch OpenVPN")
            case .management:
                self.updateStatusUI(connected: false, statusDescription: "Failed to Connect to the Management Server")
            case .statusCodes:
                self.updateStatusUI(connected: false, statusDescription: "Failed to connect  to OpenVPN")
            }
        }
    }
    
    func populateServerSelectButton()
    {
        serverSelectButton.removeAllItems()
        serverSelectButton.addItem(withTitle: ServerName.defaultServer.rawValue)
        
        if userServerIP == ""
        {
            serverSelectButton.selectItem(withTitle: ServerName.defaultServer.rawValue)
            setSelectedServer(title: ServerName.defaultServer.rawValue)
        }
        else
        {
            serverSelectButton.addItem(withTitle: ServerName.userServer.rawValue)
            serverSelectButton.selectItem(withTitle: ServerName.userServer.rawValue)
            setSelectedServer(title: ServerName.userServer.rawValue)
        }
    }
    
    //MARK: UI Helpers
    func styleViews()
    {
        //Title Label Styling
        if let titleFont = NSFont(name: proximaNARegular, size: 34)
        {
            let titleLabelAttributes = [NSKernAttributeName: 7.8,
                                        NSFontAttributeName: titleFont] as [String : Any]
            titleLabel.attributedStringValue = NSAttributedString(string: "MOONBOUNCE VPN", attributes: titleLabelAttributes)
        }
        
        //Connection Button and label Styling
        showStatus()
        
        //Advanced Mode Button
        if let menuButtonFont = NSFont(name: proximaNARegular, size: 18)
        {
            let menuButtonAttributes = [NSForegroundColorAttributeName: NSColor.white,
                                        NSFontAttributeName: menuButtonFont]
            advancedModeButton.attributedTitle = NSAttributedString(string: "Advanced Mode", attributes: menuButtonAttributes)
        }
        advancedModeButton.layer?.backgroundColor = .clear
        
        //Advanced Mode Box
        advancedModeHeightConstraint.constant = 0
        
        //Progress Indicator for Server Launch
        serverProgressBar.controlTint = .clearControlTint
        
        //Has the user entered their Digital Ocean Token?
        if let userToken = UserDefaults.standard.object(forKey: userTokenKey) as! String?
        {
            if userToken == ""
            {
                hasDoToken = false
            }
            else
            {
                hasDoToken = true
                print("******Found a token in user defaults!")
            }
        }
        else
        {
            hasDoToken = false
        }
        
        //Hide the account token input box if we already have a token saved
        //accountTokenBox.isHidden = !hasDoToken
    }
    
    func showMenu(sender: AnyObject?)
    {
        advancedModeHeightConstraint.constant = advancedMenuHeight
    }
    
    func closeMenu(sender: AnyObject?)
    {
        advancedModeHeightConstraint.constant = 0
    }
    
    func runBackgroundAnimation()
    {
        NSAnimationContext.runAnimationGroup(
        {
                (context) in
                context.duration = 0.75
                self.laserLeadingConstraint.animator().constant = 260
        },
        completionHandler:
        {
            NSAnimationContext.runAnimationGroup(
            {
                (context) in
                
                context.duration = 0.75
                self.laserLeadingConstraint.animator().constant = -5
            },
            completionHandler:
            {
                if isConnected.state == .trying
                //if self.runningScript == true
                {
                    self.runBackgroundAnimation()
                }
            })
        })
    }
    
    func updateStatusUI(connected: Bool, statusDescription: String)
    {
        //Update Connection Status Label
        self.statusLabel.stringValue = statusDescription
        
        if connected
        {
            //Update button name
            self.toggleConnectionButton.title = "Disconnect"
        }
        else
        {
            self.toggleConnectionButton.title = "Connect"
        }
        
        //Stop BG Animation
        self.runningScript = false
    }
    
}
