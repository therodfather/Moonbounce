//
//  MoonbounceViewController.swift
//  Moonbounce
//
//  Created by Adelita Schule on 10/24/16.
//  Copyright © 2016 operatorfoundation.org. All rights reserved.
//

import Cocoa
import NetworkExtension
import os.log

import Chord
import MoonbounceLibrary
import MoonbounceShared
import ShadowSwift

class MoonbounceViewController: NSViewController, NSSharingServicePickerDelegate
{
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var advancedModeButton: NSButton!
    @IBOutlet weak var toggleConnectionButton: CustomButton!
    @IBOutlet weak var backgroundImageView: NSImageView!
    @IBOutlet weak var laserImageView: NSImageView!
    @IBOutlet weak var laserLeadingConstraint: NSLayoutConstraint!

    @objc dynamic var runningScript = false
    
    //Advanced Mode Outlets
    @IBOutlet weak var advModeHeightConstraint: NSLayoutConstraint!
    
    let proximaNARegular = "Proxima Nova Alt Regular"
    let advancedMenuHeight: CGFloat = 176.0
    let moonbounce = MoonbounceLibrary(logger: Logger(subsystem: "org.OperatorFoundation.MoonbounceLogger", category: "NetworkExtension"))
    var loggingEnabled = false

    let worker: DispatchQueue = DispatchQueue(label: "MoonbounceViewController.worker")
    
    //MARK: View Life Cycle
    
    override func viewDidLoad()
    {
        super.viewDidLoad()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSNotification.Name(rawValue: kConnectionStatusNotification), object: nil, queue: nil, using: connectionStatusChanged)
        nc.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: nil, queue: nil, using: neVPNStatusChanged)
        
        advancedModeButton.isHidden = true
        updateStatusUI(connected: false, statusDescription: "Not Connected")

        self.worker.async
        {
            let appId = Bundle.main.bundleIdentifier!
            let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("moonbounce.json")
            
            do
            {
                let decoder = JSONDecoder()
                let decodedData = try Data(contentsOf: configURL)
                let clientConfig = try decoder.decode(ClientConfig.self, from: decodedData)
                
                guard clientConfig.serverPublicKey.data != nil else
                {
                    throw MoonbounceConfigError.serverPublicKeyInvalid
                }
                                
                let shadowConfig = try ShadowConfig.ShadowClientConfig(serverAddress: "\(clientConfig.host):\(UInt16(clientConfig.port))", serverPublicKey: clientConfig.serverPublicKey, mode: .DARKSTAR)
                
                print("☾ Saving moonbounce configuration with \nip: \(clientConfig.host)\nport: \(clientConfig.port)\nproviderBundleIdentifier: \(appId).NetworkExtension")
                try self.moonbounce.configure(shadowConfig, providerBundleIdentifier: "\(appId).NetworkExtension", tunnelName: "MoonbounceTunnel")
            }
            catch
            {
                print("☾ Failed to load the moonbounce configuration file at \(configURL.path()) please ensure that you have a valid file at this location.")
                print("☾ error loading configuration file: \(error)")
            }
        }
    }
    
    override func viewWillAppear()
    {
        super.viewWillAppear()
        self.styleViews()
    }
    
    func connectionStatusChanged(notification: Notification)
    {
        print("☾ Received a status changed notification:")
        
        if let session = notification.object as? NETunnelProviderSession
        {
            let status = session.status
            self.printConnectionStatus(status: status)
        }
        else
        {
            print("☾ \(notification.object!)")
        }
        
//        showStatus()
    }
    
    func neVPNStatusChanged(notification: Notification)
    {
        print("☾ Received a neVPNStatusChanged changed notification:")
        
        if let session = notification.object as? NETunnelProviderSession
        {
            let status = session.status
            self.printConnectionStatus(status: status)
        }
        else
        {
            print("☾ \(notification.object!)")
        }
        
//        showStatus()
    }
    
    func printConnectionStatus( status: NEVPNStatus )
    {
        switch status 
        {
            case NEVPNStatus.invalid:
                print("☾ NEVPNConnection: Invalid")
                updateStatusUI(connected: false, statusDescription: "Invalid")
            case NEVPNStatus.disconnected:
                print("☾ NEVPNConnection: Disconnected")
                updateStatusUI(connected: false, statusDescription: "Disconnected")
            case NEVPNStatus.connecting:
                print("☾ NEVPNConnection: Connecting")
                updateStatusUI(connected: false, statusDescription: "Connecting")
            case NEVPNStatus.connected:
                print("☾ NEVPNConnection: Connected")
                updateStatusUI(connected: true, statusDescription: "Connected")
            case NEVPNStatus.reasserting:
                print("☾ NEVPNConnection: Reasserting")
                updateStatusUI(connected: true, statusDescription: "Reasserting")
            case NEVPNStatus.disconnecting:
                print("☾ NEVPNConnection: Disconnecting")
                updateStatusUI(connected: true, statusDescription: "Disconnecting")
            default:
                print("☾ NEVPNConnection: Unknown Status")
                updateStatusUI(connected: false, statusDescription: "Unknown")
      }
    }
    
    //MARK: Action!
    @IBAction func toggleConnection(_ sender: NSButton)
    {
        print("☾ User toggled connection switch.")
        print("☾ isConnected.state - \(isConnected.state), isConnected.stage - \(isConnected.stage)")
        switch isConnected.state
        {
            case .start:
                switch isConnected.stage
                {
                    case .start:
                        print("☾ Calling connect()")
                        self.connect()
                    default:
                        print("☾ We are in the start state so we expected start stage, but we got: \(isConnected.stage) stage. Doing nothing.")
                }
            case .trying:
                switch isConnected.stage
                {
                    case .start:
                        //Should Not Happen
                        print("☾ We are in the trying state and the start stage at the same time, this is considered an error. Doing nothing.")
                        appLog.error("Error: Connected state of Trying but Stage is Start")
                    default:
                        // Disconnect from VPN server
                        print("☾ Calling disconnect()")
                        disconnect()
                }
            case .success:
                print("☾ Calling disconnect()")
                disconnect()
            case .failed:
                print("☾ Calling connect()")
                connect()
        }
    }
    
    @IBAction func showAdvancedMode(_ sender: AnyObject)
    {
        if advModeHeightConstraint.constant > 0
        {
            closeMenu(sender: sender)
        }
        else
        {
            showMenu(sender: sender)
        }
    }
    
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService]
    {
        print("☾ Share services: \(proposedServices)")
        
        return proposedServices
    }
    
    
    func connect()
    {
        isConnected.stage = .start
        isConnected.state = .trying

        runBackgroundAnimation()
        isConnected = ConnectState(state: .start, stage: .start)
        runningScript = true
        
        // Update button name
        self.toggleConnectionButton.title = "Disconnect"

        Asynchronizer.asyncThrows(moonbounce.startVPN)
        {
            maybeError in

            if let error = maybeError
            {
                isConnected.state = .failed
                print("☾ moonbounce.startVPN() returned an error: \(error). Setting isConnected.state to failed.")
//                appLog.error("moonbounce.startVPN() returned an error: \(error). Setting isConnected.state to failed.")

                DispatchQueue.main.async
                {
                    self.showStatus()
                }
            }
            else
            {
                // Verify that connection was successful and update accordingly
                print("☾ moonbounce.startVPN() returned without error. Setting isConnected.state to success and the stage to statusCodes.")
                self.runningScript = false
                isConnected.state = .success
                isConnected.stage = .statusCodes

                DispatchQueue.main.async
                {
                    self.showStatus()
                }
            }
        }
    }
        
    func disconnect()
    {
        Asynchronizer.asyncThrows(moonbounce.stopVPN)
        {
            maybeError in

            if let error = maybeError
            {
                print("☾ Failed to disconnect from the VPN. Error: \(error)")
//                appLog.error("Failed to disconnect from the VPN. Error: \(error)")
            }

            self.runningScript = false
        }
    }
    
    // MARK: - UI Helpers
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
                        print("☾ Start state with \(isConnected.stage) stage. Expected start stage.")
                }
            case .trying:
                switch isConnected.stage
                {
                    case .start:
                        print("☾ Trying state with start stage. This is unexpected behavior.")
                    case .dispatcher:
                        self.updateStatusUI(connected: true, statusDescription: "Starting Dispatcher")
                    case .management:
                        self.updateStatusUI(connected: true, statusDescription: "Connecting to the Management Server")
                    case .statusCodes:
                        self.updateStatusUI(connected: true, statusDescription: "Getting VPN Status")
                }
            case .success:
                switch isConnected.stage
                {
                    case .start:
                        print("☾ Success state with start stage. This is unexpected behavior.")
                    case .dispatcher:
                        self.updateStatusUI(connected: true, statusDescription: "Started Dispatcher")
                    case .management:
                        self.updateStatusUI(connected: true, statusDescription: "Connected to the Management Server")
                    case .statusCodes:
                        self.updateStatusUI(connected: true, statusDescription: "Connected")
                }
            case .failed:
                switch isConnected.stage
                {
                    case .start:
                        print("☾ Failed state with start stage. This is unexpected behavior.")
                    case .dispatcher:
                        self.updateStatusUI(connected: false, statusDescription: "Failed to start Dispatcher")
                    case .management:
                        self.updateStatusUI(connected: false, statusDescription: "Failed to Connect to the Management Server")
                    case .statusCodes:
                        self.updateStatusUI(connected: false, statusDescription: "Failed to connect  to VPN")
            }
        }
    }
    

    func styleViews()
    {
        //Connection Button and label Styling
        showStatus()
                
        //Advanced Mode Button
        if let menuButtonFont = NSFont(name: proximaNARegular, size: 18)
        {
            let menuButtonAttributes = [NSAttributedString.Key.foregroundColor: NSColor.white,
                                        NSAttributedString.Key.font: menuButtonFont]
            advancedModeButton.attributedTitle = NSAttributedString(string: "Advanced Mode", attributes: menuButtonAttributes)
        }
        advancedModeButton.layer?.backgroundColor = .clear
        
        //Advanced Mode Box
        advModeHeightConstraint.constant = 0
    }

    
    func showMenu(sender: AnyObject?)
    {
        advModeHeightConstraint.constant = advancedMenuHeight
    }
    
    func closeMenu(sender: AnyObject?)
    {
        advModeHeightConstraint.constant = 0
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
        DispatchQueue.main.async
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
    
    @objc func animateLoadingLabel()
    {
        if statusLabel.stringValue == "Loading..."
        {
            statusLabel.stringValue = "Loading"
        }
        else
        {
            statusLabel.stringValue = "\(statusLabel.stringValue)."
        }
        
        perform(#selector(animateLoadingLabel), with: nil, afterDelay: 1)
    }
    
    //Helper for showing an alert.
    func showAlert(_ message: String)
    {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

public enum MoonbounceConfigError: Error {
    case serverPublicKeyInvalid
}
