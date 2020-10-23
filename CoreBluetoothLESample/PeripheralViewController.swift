/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class to advertise, send notifications and receive data from central looking for transfer service and characteristic.
*/

import UIKit
import CoreBluetooth
import os

class PeripheralViewController: UIViewController {

    @IBOutlet var textView: UITextView!
    @IBOutlet var advertisingSwitch: UISwitch!
    @IBOutlet var inputTextField: UITextField!
    @IBOutlet var sendButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    
    var peripheralManager: CBPeripheralManager!
    var transferCharacteristic_Rx: CBMutableCharacteristic?
    var transferCharacteristic_Tx: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    var peripheral: CBPeripheral!
    var dataToSend = Data()
    var sendDataIndex: Int = 0
    private var consoleAsciiText: NSAttributedString? = NSAttributedString(string: "")
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        super.viewDidLoad()
        textView.isUserInteractionEnabled = true
        textView.isEditable = false
        textView.isSelectable = false
        updateIncomingData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        // Don't keep advertising going while we're not showing.
        peripheralManager.stopAdvertising()
        super.viewWillDisappear(animated)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
    
    @IBAction func getText(sender: UITextField) {
    }
    // MARK: - Switch Methods

    @IBAction func switchChanged(_ sender: Any) {
        // All we advertise is our service's UUID.
        if advertisingSwitch.isOn {
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID]])
        } else {
            peripheralManager.stopAdvertising()
        }
    }
    
    @IBAction func clickSendAction(_ sender: AnyObject) {
        outgoingData()
    }
    
    func outgoingData() {
        let appendString = "\n"
        let inputText = inputTextField.text
        let myFont = UIFont(name: "Helvetica Neue", size: 15.0)
        let myAttributes1 = [convertFromNSAttributedStringKey(NSAttributedString.Key.font): myFont!, convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UIColor.blue]
        writeValue(data: inputText!)
        let attribString = NSAttributedString(string: "[Peripheral]: " + inputText! + appendString, attributes: convertToOptionalNSAttributedStringKeyDictionary(myAttributes1))
        let newAsciiText = NSMutableAttributedString(attributedString: self.consoleAsciiText!)
        newAsciiText.append(attribString)
        
        consoleAsciiText = newAsciiText
        textView.attributedText = consoleAsciiText
        inputTextField.text = ""
    }
    
    func writeValue(data: String) {
        let valueString = (data as NSString).data(using: String.Encoding.utf8.rawValue)
        if let discoveredPeripheral = discoveredPeripheral {
            if let txCharacteristic = txCharacteristic {
                discoveredPeripheral.writeValue(valueString!, for: txCharacteristic, type: CBCharacteristicWriteType.withResponse)
            }
        }
    }
    
    func updateIncomingData() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "Notify"), object: nil , queue: nil){
            notification in
            let appendString = "\n"
            let myFont = UIFont(name: "Helvetica Neue", size: 15.0)
            let myAttributes2 = [convertFromNSAttributedStringKey(NSAttributedString.Key.font): myFont!, convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UIColor.red]
            let attribString = NSAttributedString(string: "[Central]: " + (characteristicASCIIValue as String) + appendString, attributes: convertToOptionalNSAttributedStringKeyDictionary(myAttributes2))
            let newAsciiText = NSMutableAttributedString(attributedString: self.consoleAsciiText!)
            self.textView.attributedText = NSAttributedString(string: characteristicASCIIValue as String , attributes: convertToOptionalNSAttributedStringKeyDictionary(myAttributes2))
            
            newAsciiText.append(attribString)
            
            self.consoleAsciiText = newAsciiText
            self.textView.attributedText = self.consoleAsciiText
        }
    }

    // MARK: - Helper Methods

    /*
     *  Sends the next amount of data to the connected central
     */
    static var sendingEOM = false
    
    private func sendData() {
		
		guard let transferCharacteristic = transferCharacteristic_Tx
        else {
			return
		}
		
        // First up, check if we're meant to be sending an EOM
        if PeripheralViewController.sendingEOM {
            // send it
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                PeripheralViewController.sendingEOM = false
                os_log("Sent: EOM")
            }
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        
        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if sendDataIndex >= dataToSend.count {
            // No data left.  Do nothing
            return
        }
        
        // There's data left, so send until the callback fails, or we're done.
        var didSend = true
        while didSend {
            
            // Work out how big it should be
            var amountToSend = dataToSend.count - sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                amountToSend = min(amountToSend, mtu)
            }
            
            // Copy out the data we want
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
            
            // Send it
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            
            // If it didn't work, drop out and wait for the callback
            if !didSend {
                return
            }
            
            let stringFromData = String(data: chunk, encoding: .utf8)
            os_log("Sent %d bytes: %s", chunk.count, String(describing: stringFromData))
            
            // It did send, so update our index
            sendDataIndex += amountToSend
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                PeripheralViewController.sendingEOM = true
                
                //Send it
                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                             for: transferCharacteristic, onSubscribedCentrals: nil)
                
                if eomSent {
                    // It sent; we're all done
                    PeripheralViewController.sendingEOM = false
                    os_log("Sent: EOM")
                }
                return
            }
        }
    }

    private func setupPeripheral() {
        
        // Build our service.
        
        // Start with the CBMutableCharacteristic.
        let transferCharacteristic_Tx = CBMutableCharacteristic(type: TransferService.characteristic_Tx_UUID, properties: [.notify, .writeWithoutResponse], value: nil, permissions: [.readable, .writeable])
        
        // Create a service from the characteristic.
        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)
        let transferCharacteristic_Rx  =  CBMutableCharacteristic(type: TransferService.characteristic_Rx_UUID, properties: [.read, .notify], value: nil, permissions: [.readable, .writeable])
        // Add the characteristic to the service.
        transferService.characteristics = [transferCharacteristic_Rx, transferCharacteristic_Tx]
        
        // And add it to the peripheral manager.
        peripheralManager.add(transferService)
        
        // Save the characteristic for later.
        self.transferCharacteristic_Tx = transferCharacteristic_Tx
        self.transferCharacteristic_Rx = transferCharacteristic_Rx
    }
}

extension PeripheralViewController: CBPeripheralManagerDelegate {
    // implementations of the CBPeripheralManagerDelegate methods

    /*
     *  Required protocol method.  A full app should take care of all the possible states,
     *  but we're just waiting for to know when the CBPeripheralManager is ready
     *
     *  Starting from iOS 13.0, if the state is CBManagerStateUnauthorized, you
     *  are also required to check for the authorization state of the peripheral to ensure that
     *  your app is allowed to use bluetooth
     */
    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        
        advertisingSwitch.isEnabled = peripheral.state == .poweredOn
        
        switch peripheral.state {
        case .poweredOn:
            // ... so start working with the peripheral
            os_log("CBManager is powered on")
            setupPeripheral()
        case .poweredOff:
            os_log("CBManager is not powered on")
            // In a real app, you'd deal with all the states accordingly
            return
        case .resetting:
            os_log("CBManager is resetting")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unauthorized:
            // In a real app, you'd deal with all the states accordingly
            if #available(iOS 13.0, *) {
                switch peripheral.authorization {
                case .denied:
                    os_log("You are not authorized to use Bluetooth")
                case .restricted:
                    os_log("Bluetooth is restricted")
                default:
                    os_log("Unexpected authorization")
                }
            } else {
                // Fallback on earlier versions
            }
            return
        case .unknown:
            os_log("CBManager state is unknown")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
            // In a real app, you'd deal with all the states accordingly
            return
        @unknown default:
            os_log("A previously unknown peripheral manager state occurred")
            // In a real app, you'd deal with yet unknown cases that might occur in the future
            return
        }
    }

    /*
     *  Catch when someone subscribes to our characteristic, then start sending them data
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        os_log("Central subscribed to characteristic")
        
        // Get the data
        dataToSend = textView.text.data(using: .utf8)!
        
        // Reset the index
        sendDataIndex = 0
        
        // save central
        connectedCentral = central
        
        // Start sending
        sendData()
        updateIncomingData()
    }
    
    /*
     *  Recognize when the central unsubscribes
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        os_log("Central unsubscribed from characteristic")
        connectedCentral = nil
    }
    
    /*
     *  This callback comes in when the PeripheralManager is ready to send the next chunk of data.
     *  This is to ensure that packets will arrive in the order they are sent
     */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }
    
    /*
     * This callback comes in when the PeripheralManager received write to characteristics
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            guard let requestValue = aRequest.value,
                let stringFromData = String(data: requestValue, encoding: .utf8) else {
                    continue
            }
            
            os_log("Received write request of %d bytes: %s", requestValue.count, stringFromData)
            self.textView.text = stringFromData
            updateIncomingData()
        }
    }
}

extension PeripheralViewController: UITextViewDelegate {
    // implementations of the UITextViewDelegate methods

    /*
     *  This is called when a change happens, so we know to stop advertising
     */
    func textViewDidChange(_ textView: UITextView) {
        // If we're already advertising, stop
        if advertisingSwitch.isOn {
            advertisingSwitch.isOn = false
            peripheralManager.stopAdvertising()
        }
    }
    
    /*
     *  Adds the 'Done' button to the title bar
     */
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        outgoingData()
        return(true)
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        // We need to add this manually so we have a way to dismiss the keyboard
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }
    
    /*
     * Finishes the editing
     */
    @objc
    func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }
    
}
fileprivate func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
    return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
    guard let input = input else { return nil }
    return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}

