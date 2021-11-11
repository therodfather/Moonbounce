//
//  File.swift
//  MoonbounceiOSNetworkExtension
//
//  Created by Mafalda on 2/12/19.
//  Copyright © 2019 Operator Foundation. All rights reserved.
//

import Foundation
import Logging
import NetworkExtension
import ReplicantSwiftClient
import Flower
import InternetProtocols

/// An object used to tunnel IP packets using the SimpleTunnel protocol.
public class ClientTunnelConnection
{
    /// The flow of IP packets.
    let packetFlow: NEPacketTunnelFlow
    let log: Logger
    let flowerConnection: FlowerConnection
    var ipAllocationMessage: Message? = nil
    let messagesToPacketsQueue = DispatchQueue(label: "clientTunnelConnection: messagesToPackets")
    let packetsToMessagesQueue = DispatchQueue(label: "clientTunnelConnection: packetsToMessages")
    
    // MARK: Initializers
    public init(clientPacketFlow: NEPacketTunnelFlow, flowerConnection: FlowerConnection, logger: Logger)
    {
        self.log = logger
        self.packetFlow = clientPacketFlow
        self.flowerConnection = flowerConnection
        logger.debug("Initialized ClientTunnelConnection")
    }

//    // MARK: Interface
//
//    /// Wait for IP assignment from the server
//    public func waitForIPAssignment()
//    {
//        replicantConnection.readMessages(log: self.log)
//        {
//            (message) in
//
//            self.log.debug("🌷 replicantConnection.readMessages callback message: \(message.description) 🌷")
//            switch message
//            {
//                case .IPAssignV4(_),
//                     .IPAssignV6(_):
//                     //.IPAssignDualStack(_, _):
//                    guard self.ipAllocationMessage == nil else {break}
//                    self.ipAllocationMessage = message
//                case .IPDataV4(let data):
//                    self.log.debug("IPDataV4 calling write packets.")
//                    self.packetFlow.writePackets([data], withProtocols: [4])
//                case .IPDataV6(let data):
//                    self.log.debug("IPDataV6 calling write packets.")
//                    self.packetFlow.writePackets([data], withProtocols: [6])
//                default:
//                    self.log.error("unsupported message type")
//            }
//        }
//
//    }
    
    /// Make the initial readPacketsWithCompletionHandler call.
    public func startHandlingPackets()
    {
        self.log.debug("7. Start handling packets called.")
        
        packetsToMessagesQueue.async
        {
            self.log.debug("calling packetsToMessages async")
            self.packetsToMessages()
        }
        
        messagesToPacketsQueue.async
        {
            self.log.debug("calling messagesToPackets async")
            self.messagesToPackets()
        }
    }
    
    /// Handle packets coming from the packet flow.
    func packetsToMessages()
    {
        log.debug("8. Handle Packets Called")
        // This is where you should send the packets to the server.

        // Read more packets.
        let lock = DispatchGroup()

        while true
        {
            lock.enter()
            self.packetFlow.readPackets
            {
                (inPackets, inProtocols) in

                self.log.debug("Reached the readPackets callback :)")

                let packages = zip(inPackets, inProtocols)

                for (packet, prot) in packages
                {
                    // Check if protocol is v4 or v6
                    switch prot
                    {
                        case NSNumber(value: AF_INET):
                            self.log.debug("Ipv4 protocol")

                            // Encapsulates packages into Messages (using Flower)
                            self.log.debug("packet: \(packet)")
                            let message = Message.IPDataV4(packet)
                            self.log.debug("🌷 encapsulated into Flower Message: \(message.description) 🌷")

                            self.flowerConnection.writeMessage(message: message)
                        case NSNumber(value: AF_INET6):
                            self.log.debug("IPv6 protocol")
                            let message = Message.IPDataV6(packet)
                            self.flowerConnection.writeMessage(message: message)
                        default:
                            self.log.error("Unsupported protocol type: \(prot)")
                    }
                }

                lock.leave()
            }

            lock.wait()
        }
    }
        
    func messagesToPackets()
    {
        while true
        {
            guard let message = flowerConnection.readMessage() else {return}

            self.log.debug("🌷 replicantConnection.readMessages callback message: \(message.description) 🌷")
            switch message
            {
                case .IPDataV4(let data):
                    self.log.debug("IPDataV4 calling write packets.")
                    self.packetFlow.writePackets([data], withProtocols: [4])
                case .IPDataV6(let data):
                    self.log.debug("IPDataV6 calling write packets.")
                    self.packetFlow.writePackets([data], withProtocols: [6])
                default:
                    self.log.error("unsupported message type")
            }
        }
    }
}
