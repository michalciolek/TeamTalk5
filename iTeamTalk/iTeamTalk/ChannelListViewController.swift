/*
* Copyright (c) 2005-2016, BearWare.dk
*
* Contact Information:
*
* Bjoern D. Rasmussen
* Kirketoften 5
* DK-8260 Viby J
* Denmark
* Email: contact@bearware.dk
* Phone: +45 20 20 54 59
* Web: http://www.bearware.dk
*
* This source code is part of the TeamTalk 5 SDK owned by
* BearWare.dk. All copyright statements may not be removed
* or altered from any source distribution. If you use this
* software in a product, an acknowledgment in the product
* documentation is required.
*
*/

import UIKit
import AVFoundation
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


class ChannelListViewController :
    UIViewController, UITableViewDataSource,
    UITableViewDelegate, UIAlertViewDelegate,
    MyTextMessageDelegate, TeamTalkEvent  {

    // all channels on server
    var channels = [INT32 : Channel]()
    // channel passwords
    var chanpasswds = [INT32 : String]()
    // the channel being displayed (not nescessarily the same channel as we're in)
    var curchannel = Channel()
    // joined channel (the channel we're in)
    var mychannel = Channel()
    // channel to join if connection is lost
    var rejoinchannel = Channel()
    // all users on server
    var users = [INT32 : User]()
    // users which should be moved
    var moveusers = [INT32]()
    // the ID of the command for which we're expecting a result
    var cmdid : INT32 = 0
    // the command ID which is currently processing
    var currentCmdId : INT32 = 0
    // the commands awaiting reponse
    var activeCommands = [INT32: Command]()
    // properties of connected server
    var srvprop = ServerProperties()
    // local instance's user account
    var myuseraccount = UserAccount()
    // user to user text messages
    var textmessages = [INT32 : [MyTextMessage] ]()
    // timer for blinking unread messages
    var unreadTimer : Timer?
    // list of channels and users
    @IBOutlet weak var tableView: UITableView!
    // PTT button
    @IBOutlet weak var txButton: UIButton!
    // timeout for PTT lock
    var pttLockTimeout = Date()

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
    
        updateTX()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        tableView.reloadData()
        updateTX()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func joinChannel(_ sender: UIButton) {
        joinNewChannel(curchannel)
    }
    
    func joinNewChannel(_ channel: Channel) {
        if channel.bPassword != 0 {
            let alertView = UIAlertView(title: NSLocalizedString("Enter Password", comment: "Dialog message"), message: NSLocalizedString("Password", comment: "Dialog message"), delegate: self, cancelButtonTitle: NSLocalizedString("Join", comment: "Dialog message"))
            alertView.alertViewStyle = .secureTextInput
            alertView.tag = Int(channel.nChannelID)
            if let passwd = chanpasswds[channel.nChannelID] {
                alertView.textField(at: 0)?.text = passwd
            }
            alertView.show()
        }
        else {
            cmdid = TT_DoJoinChannelByID(ttInst, channel.nChannelID, "")
            activeCommands[cmdid] = .joinCmd
        }
        
    }
    
    func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        let passwd = (alertView.textField(at: 0)?.text)!
        chanpasswds[INT32(alertView.tag)] = passwd
        cmdid = TT_DoJoinChannelByID(ttInst, INT32(alertView.tag), passwd)
        activeCommands[cmdid] = .joinCmd
    }
    
    func appendTextMessage(_ userid: INT32, txtmsg: MyTextMessage) {
        
        if textmessages[userid] == nil {
            textmessages[userid] = [MyTextMessage]()
        }
        textmessages[userid]?.append(txtmsg)
        
        if textmessages[userid]?.count > MAX_TEXTMESSAGES {
            textmessages[userid]?.removeFirst()
        }
    }
    
    func getUsersCount(_ chanid: INT32) -> Int {
        
        let chanusers : [User] = users.values.filter({$0.nChannelID == chanid})
        
        return chanusers.count
    }
    
    func getDisplayItems() -> ([Channel], [User]) {
        let subchans : [Channel] = channels.values.filter({$0.nParentID == self.curchannel.nChannelID})
        let chanusers : [User] = users.values.filter({$0.nChannelID == self.curchannel.nChannelID})
        
        return (subchans, chanusers)
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        let (subchans, chanusers) = getDisplayItems()
        
        var n_items = subchans.count + chanusers.count
        
        if curchannel.nChannelID != mychannel.nChannelID && curchannel.nChannelID > 0 {
            n_items += 1 // +1 for 'Join this channel'
        }
        
        if curchannel.nParentID != 0 {
            n_items += 1 //+1 for 'Back' to parent channel
        }
        return n_items
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let (subchans, chanusers) = getDisplayItems()

        //print("row = \(indexPath.row) cur channel = \(curchannel.nChannelID) subs = \(subchans.count) users = \(chanusers.count)")

        let show_join = curchannel.nChannelID != mychannel.nChannelID && curchannel.nChannelID > 0
        let show_parent = curchannel.nParentID != 0
        
        // for some absurd reason UITableView::numberOfRowsInSection() and UITableView::cellForRowAt()
        // can be interleaved when calling UITableView::reloadData() so row-count and data to be 
        // displayed (self.channels and self.users) are out of sync
        var display_rows = subchans.count + chanusers.count
        if show_join {
            display_rows += 1
        }
        if show_parent {
            display_rows += 1
        }
        
        if indexPath.row >= display_rows {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        
        // current index for users
        var user_index = indexPath.row
        if show_join {
            user_index -= 1
        }
        
        if show_join && indexPath.row == 0 {
            let cellIdentifier = "JoinChannelCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
            return cell
        }
        
        if user_index < chanusers.count {
            
            let cellIdentifier = "UserTableCell"
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! UserTableCell
            let user = chanusers[user_index]
            let name = getDisplayName(user)
            let statusmsg = fromTTString(user.szStatusMsg)
            
            cell.nicknameLabel.text = name
            cell.statusmsgLabel.text = statusmsg
            
            cell.userImage.accessibilityLabel = NSLocalizedString("User", comment: "channel list")
            if user.uUserState & USERSTATE_VOICE.rawValue != 0 ||
                (TT_GetMyUserID(ttInst) == user.nUserID &&
                    isTransmitting(ttInst!, stream: STREAMTYPE_VOICE)) {
                        
                cell.userImage.image = UIImage(named: "man_green.png")
                cell.userImage.accessibilityHint = NSLocalizedString("Talking", comment: "channel list")
            }
            else {
                cell.userImage.image = UIImage(named: "man_blue.png")
                cell.userImage.accessibilityHint = NSLocalizedString("Silent", comment: "channel list")
            }
            
            cell.messageBtn.tag = Int(user.nUserID)
            cell.tag = Int(user.nUserID)
            
            if #available(iOS 8.0, *) {
                let action_msg = MyCustomAction(name: NSLocalizedString("Send private message", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.messageUser(_:)), tag: cell.tag)
                let action_mute = MyCustomAction(name: NSLocalizedString("Mute", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.muteUser(_:)), tag: cell.tag)
                
                var actions = [MyCustomAction]()
                actions.append(action_msg)
                actions.append(action_mute)
                
                if (myuseraccount.uUserRights & USERRIGHT_MOVE_USERS.rawValue) != 0 {
                    let action_move = MyCustomAction(name: NSLocalizedString("Move user", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.moveUser(_:)), tag: cell.tag)
                    actions.append(action_move)
                }
                
                let op = TT_IsChannelOperator(ttInst, TT_GetMyUserID(ttInst), user.nChannelID) == TRUE
                if (myuseraccount.uUserRights & USERRIGHT_KICK_USERS.rawValue) != 0 || op {
                    let action_kick = MyCustomAction(name: NSLocalizedString("Kick user", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.kickUser(_:)), tag: cell.tag)
                    actions.append(action_kick)
                }
                cell.accessibilityCustomActions = actions
            } else {
                // Fallback on earlier versions
            }
            
            return cell
        }

        // current index for channels
        var chan_index = indexPath.row - chanusers.count
        if show_join {
            chan_index -= 1
        }
        
        let cellIdentifier = "ChannelTableCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! ChannelTableCell
        
        var channel = Channel()
        var textcolor : UIColor? = nil
        var title : String?, subtitle : String?
        
        cell.chanimage.accessibilityLabel = NSLocalizedString("Channel", comment: "channel list")
        
        if curchannel.nChannelID == 0 {
            
            // display only the root channel
            
            assert(subchans.count == 1) //only sub channel should be the root channel
            
            channel = subchans[chan_index]
            
            title = fromTTString(srvprop.szServerName)
            subtitle = fromTTString(channel.szTopic)
            
            if channel.bPassword != 0 {
                cell.chanimage.image = UIImage(named: "channel_pink.png")
                cell.chanimage.accessibilityHint = NSLocalizedString("Password protected", comment: "channel list")
            }
            else {
                cell.chanimage.image = UIImage(named: "channel_orange.png")
                cell.chanimage.accessibilityHint = NSLocalizedString("No password", comment: "channel list")
            }
        }
        else if chan_index == 0 && show_parent {
            
            // display previous channel if not in root channel
            
            channel = channels[curchannel.nParentID]!
            
            title = NSLocalizedString("Parent channel", comment: "channel list")
            if channel.nParentID == 0 {
                subtitle = fromTTString(srvprop.szServerName)
            }
            else {
                subtitle = fromTTString(channel.szName)
            }
            
            textcolor = UIColor.gray
            cell.chanimage.image = UIImage(named: "back_orange.png")
            cell.chanimage.accessibilityHint = NSLocalizedString("Return to previous channel", comment: "channel list")
        }
        else {
            
            // display sub channels
            
            if show_parent {
                chan_index -= 1
            }

            assert(chan_index >= 0)
            assert(chan_index < subchans.count)
            
            channel = subchans[chan_index]
            
            let user_count = getUsersCount(channel.nChannelID)
            title = fromTTString(channel.szName) + " (\(user_count))"
            subtitle = fromTTString(channel.szTopic)
            
            if channel.bPassword != 0 {
                cell.chanimage.image = UIImage(named: "channel_pink.png")
                cell.chanimage.accessibilityHint = NSLocalizedString("Password protected", comment: "channel list")
            }
            else {
                cell.chanimage.image = UIImage(named: "channel_orange.png")
                cell.chanimage.accessibilityHint = NSLocalizedString("No password", comment: "channel list")
            }
            
            cell.chanimage.accessibilityLabel =
                String(format: NSLocalizedString("Channel. %d users", comment: "channel list"), user_count)
        }
        
        cell.channame.textColor = textcolor
        cell.chantopicLabel.textColor = textcolor
        
        cell.channame.text = limitText(title!)
        cell.chantopicLabel.text = subtitle
        
        cell.editBtn.tag = Int(channel.nChannelID)
        cell.tag = Int(channel.nChannelID)
        
        if #available(iOS 8.0, *) {
            
            var actions = [MyCustomAction]()

            if moveusers.count > 0 {
                let action_move = MyCustomAction(name: NSLocalizedString("Move users here", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.moveIntoChannel(_:)), tag: cell.tag)
                actions.append(action_move)
            }
            
            if channel.nChannelID != mychannel.nChannelID {
                let action_join = MyCustomAction(name: NSLocalizedString("Join channel", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.joinThisChannel(_:)), tag: cell.tag)
                actions.append(action_join)
            }

            let op = TT_IsChannelOperator(ttInst, TT_GetMyUserID(ttInst), channel.nChannelID) == TRUE
            if (myuseraccount.uUserRights & USERRIGHT_MODIFY_CHANNELS.rawValue) != 0 || op {
                let action_edit = MyCustomAction(name: NSLocalizedString("Edit properties", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.editChannel(_:)), tag: cell.tag)
                actions.append(action_edit)
            }
            else {
                cell.editBtn.setTitle(NSLocalizedString("View", comment: "channel list"), for: UIControlState())
                let action_view = MyCustomAction(name: NSLocalizedString("View properties", comment: "channel list"), target: self, selector: #selector(ChannelListViewController.editChannel(_:)), tag: cell.tag)
                actions.append(action_view)
            }
            
            cell.accessibilityCustomActions = actions
        } else {
            // Fallback on earlier versions
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = self.tableView.cellForRow(at: indexPath)
        if cell is ChannelTableCell {
            curchannel = channels[INT32(cell!.tag)]!
            tableView.reloadData()
            updateTitle()
        }
    }
    
    func updateTitle() {
        var title = ""
        if curchannel.nParentID == 0 {
            title = fromTTString(srvprop.szServerName)
        }
        else {
            title = fromTTString(curchannel.szName)
        }
        
        self.tabBarController?.navigationItem.title = title
    }
    
    @available(iOS 8.0, *)
    func messageUser(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            performSegue(withIdentifier: "New TextMessage", sender: ac)
        }
        return true
    }

    @available(iOS 8.0, *)
    func muteUser(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            let userid = INT32(ac.tag)
            if let user = users[userid] {
                TT_SetUserMute(ttInst, userid, STREAMTYPE_MEDIAFILE_AUDIO,
                               (user.uUserState & USERSTATE_MUTE_MEDIAFILE.rawValue) == 0 ? TRUE : FALSE )
                TT_SetUserMute(ttInst, userid, STREAMTYPE_VOICE,
                               (user.uUserState & USERSTATE_MUTE_VOICE.rawValue) == 0 ? TRUE : FALSE )
                // tell TeamTalk event loop to send us an updated User-struct
                TT_PumpMessage(ttInst, CLIENTEVENT_USER_STATECHANGE, userid)
            }
            
        }
        return true
    }

    @available(iOS 8.0, *)
    func moveUser(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            moveusers.append(INT32(ac.tag))
            self.tableView.reloadData() //need to update accessible actions on channels
        }
        return true
    }

    @available(iOS 8.0, *)
    func kickUser(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            
            cmdid = TT_DoKickUser(ttInst, INT32(ac.tag), curchannel.nChannelID)
            activeCommands[cmdid] = .kickCmd
        }
        return true
    }

    @available(iOS 8.0, *)
    func joinThisChannel(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            if let channel = channels[INT32(ac.tag)] {
                joinNewChannel(channel)
            }
        }
        return true
    }

    @available(iOS 8.0, *)
    func editChannel(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            performSegue(withIdentifier: "Edit Channel", sender: ac)
        }
        return true
    }
    
    @available(iOS 8.0, *)
    func moveIntoChannel(_ action: UIAccessibilityCustomAction) -> Bool {
        if let ac = action as? MyCustomAction {
            for userid in moveusers {
                cmdid = TT_DoMoveUser(ttInst, userid, INT32(ac.tag))
                activeCommands[cmdid] = .moveCmd
            }
            moveusers.removeAll()
        }
        return true
    }
    
    func commandComplete(_ active_cmdid : INT32) {

        let cmd = activeCommands[active_cmdid]
        
        if cmd == nil {
            return
        }
        
        switch cmd! {
            
        case .loginCmd :
            let flags = TT_GetFlags(ttInst)
            
            if (flags & CLIENT_AUTHORIZED.rawValue) != 0 {
                
                if rejoinchannel.nChannelID > 0 {
                    // if we were previously in a channel then rejoin
                    let passwd = chanpasswds[rejoinchannel.nChannelID] != nil ? chanpasswds[rejoinchannel.nChannelID] : ""
                    toTTString(passwd!, dst: &rejoinchannel.szPassword)
                    cmdid = TT_DoJoinChannel(ttInst, &rejoinchannel)
                    activeCommands[cmdid] = .joinCmd
                }
                else if fromTTString(rejoinchannel.szName).isEmpty == false {
                    // join from initial login
                    let passwd = fromTTString(rejoinchannel.szPassword)
                    toTTString(passwd, dst: &rejoinchannel.szPassword)
                    cmdid = TT_DoJoinChannel(ttInst, &rejoinchannel)
                    activeCommands[cmdid] = .joinCmd
                }
                else if UserDefaults.standard.object(forKey: PREF_JOINROOTCHANNEL) == nil ||
                    UserDefaults.standard.bool(forKey: PREF_JOINROOTCHANNEL) {
                    //join root channel automatically (if enabled)
                    cmdid = TT_DoJoinChannelByID(ttInst, TT_GetRootChannelID(ttInst), "")
                    activeCommands[cmdid] = .joinCmd
                }
            }
        case .kickCmd :
            fallthrough
        case .joinCmd :
            fallthrough
        case .moveCmd :
            break
//        default :
//            print("Command #\(active_cmdid) is not a completion command")
        }

        activeCommands.removeValue(forKey: active_cmdid)
        
        self.tableView.reloadData()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.identifier == "Show User" {
            let index = self.tableView.indexPathForSelectedRow
            let cell = self.tableView.cellForRow(at: index!)

            let userDetail = segue.destination as! UserDetailViewController
            userDetail.userid = INT32(cell!.tag)
        }
        else if segue.identifier == "New Channel" {
            let chanDetail = segue.destination as! ChannelDetailViewController
            chanDetail.channel.nParentID = curchannel.nChannelID
            
            if chanDetail.channel.nParentID == 0 {
                let subchans = channels.values.filter({$0.nParentID == 0})
                if let root = subchans.first {
                    chanDetail.channel.nParentID = root.nChannelID
                }
            }
        }
        else if segue.identifier == "Edit Channel" {
            
            var chanid : INT32 = 0
            
            if let btn = sender as? UIButton {
                chanid = INT32(btn.tag)
            }
            if #available(iOS 8.0, *) {
                if let ac = sender as? MyCustomAction {
                    chanid = INT32(ac.tag)
                }
            } else {
                // Fallback on earlier versions
            }

            let channel = channels[chanid]
            
            let chanDetail = segue.destination as! ChannelDetailViewController
            chanDetail.channel = channel!
        }
        else if segue.identifier == "New TextMessage" {

            var userid : INT32 = -1
            if let btn = sender as? UIButton {
                userid = INT32(btn.tag)
            }
            if #available(iOS 8.0, *) {
                if let action = sender as? MyCustomAction {
                    userid = INT32(action.tag)
                }
            } else {
                // Fallback on earlier versions
            }
            
            let txtmsgView = segue.destination as! TextMessageViewController
            openTextMessages(txtmsgView, userid: userid)
        }
    }
    
    @IBAction func openTextMessages(_ segue:UIStoryboardSegue) {

        let src_vc = segue.source as! UserDetailViewController
        
        let vc = self.storyboard?.instantiateViewController(withIdentifier: "Text Message") as! TextMessageViewController
        openTextMessages(vc, userid: src_vc.userid)
        self.navigationController?.pushViewController(vc, animated: true)

    }

    func openTextMessages(_ sender: TextMessageViewController, userid: INT32) {
        sender.userid = userid
        sender.delegate = self
        addToTTMessages(sender)
        if (self.textmessages[userid] != nil) {
            sender.messages = self.textmessages[userid]!
        }
    }
    
    @IBAction func closeTextMessages(_ segue:UIStoryboardSegue) {
        
        print("Closed messages")
        
    }
    
    @IBAction func txBtnDown(_ sender: UIButton) {
        
        if hasPTTLock() {
            enableVoiceTx(true)
        }
        else {
            enableVoiceTx(!isTransmitting(ttInst!, stream: STREAMTYPE_VOICE))
        }
    }
    
    func enableVoiceTx(_ enable: Bool) {

        TT_EnableVoiceTransmission(ttInst, enable ? TRUE : FALSE)
        playSound(enable ? .tx_ON : .tx_OFF)
        updateTX()

    }
    
    func txBtnUp() {
        
        if hasPTTLock() {
            
            let now = Date()
            
            if (pttLockTimeout as NSDate).earlierDate(now) == now {
                enableVoiceTx(true)
            }
            else {
                enableVoiceTx(false)
            }
            // PTT lock is 0.5 sec
            pttLockTimeout = now.addingTimeInterval(0.5)
        }
    }
    
    @IBAction func txBtnUpInside(_ sender: UIButton) {
        txBtnUp()
    }
    
    @IBAction func txBtnUpOutside(_ sender: UIButton) {
        txBtnUp()
    }
    
    func updateTX() {
        
        let flags = TT_GetFlags(ttInst)
        
        switch flags & CLIENT_TX_VOICE.rawValue {
        case CLIENT_TX_VOICE.rawValue :
            txButton.backgroundColor = UIColor.red
            txButton.accessibilityLabel = NSLocalizedString("Stop transmit", comment: "channel list")
        default :
            txButton.backgroundColor = UIColor.green
            txButton.accessibilityLabel = NSLocalizedString("Transmit", comment: "channel list")
        }
        
        if hasPTTLock() {
            txButton.accessibilityHint = NSLocalizedString("Double tap and hold to transmit. Triple tap fast to lock transmission.", comment: "channel list")
        }
        else {
            txButton.accessibilityHint = NSLocalizedString("Toggle to enable/disable transmission", comment: "channel list")
        }
        
        tableView.reloadData()
        
    }
    
    func timerUnread() {
        let cells = tableView.visibleCells
        for c in cells {
            if c.reuseIdentifier == "UserTableCell"  {
                let cell = c as! UserTableCell
                if unreadmessages.contains(INT32(c.tag)) {
                    let time = Int(Date().timeIntervalSince1970)
                    if time % 2 == 0 {
                        cell.messageBtn.setImage(UIImage(named: "message_red"), for: UIControlState())
                    }
                    else {
                        cell.messageBtn.setImage(UIImage(named: "message_blue"), for: UIControlState())
                    }
                }
                else {
                    cell.messageBtn.setImage(UIImage(named: "message_blue"), for: UIControlState())
                }
            }
        }
        if unreadmessages.isEmpty {
            unreadTimer?.invalidate()
        }
    }
    
    func handleTTMessage(_ m: TTMessage) {
        var m = m
        
        switch(m.nClientEvent) {

        case CLIENTEVENT_CON_LOST :
            
            channels.removeAll()
            users.removeAll()
            curchannel = Channel()
            mychannel = Channel()
            activeCommands.removeAll()
            
            tableView.reloadData()
            break
            
        case CLIENTEVENT_CMD_PROCESSING :
            if getTTBOOL(&m) == TRUE {
                // command active
                self.currentCmdId = m.nSource
            }
            else {
                // command complete
                self.currentCmdId = 0
                
                commandComplete(m.nSource)
            }
        case CLIENTEVENT_CMD_ERROR :
            if activeCommands[m.nSource] != nil {
                let errmsg = getClientErrorMsg(&m).pointee
                let s = fromTTString(errmsg.szErrorMsg)
                if #available(iOS 8.0, *) {
                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "Dialog"), message: s, preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Dialog"), style: UIAlertActionStyle.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                } else {
                    // Fallback on earlier versions
                }
            }
        case CLIENTEVENT_CMD_SERVER_UPDATE :
            srvprop = getServerProperties(&m).pointee
            
        case CLIENTEVENT_CMD_MYSELF_LOGGEDIN :
            myuseraccount = getUserAccount(&m).pointee
            if (myuseraccount.uUserType & USERTYPE_ADMIN.rawValue) != 0 {
                // an admin user type can do everything
                myuseraccount.uUserRights = 0xFFFFFFFF
            }
            
        case CLIENTEVENT_CMD_CHANNEL_NEW :
            let channel = getChannel(&m).pointee
            
            channels[channel.nChannelID] = channel
            
            // initial title will be server name
            if channel.nParentID == 0 {
                updateTitle()
            }
            
            if currentCmdId == 0 {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_CHANNEL_UPDATE :
            let channel = getChannel(&m).pointee
            channels[channel.nChannelID] = channel
            
            if currentCmdId == 0 {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_CHANNEL_REMOVE :
            let channel = getChannel(&m).pointee
            channels.removeValue(forKey: channel.nChannelID)
            
            if currentCmdId == 0 {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_USER_LOGGEDIN :
            let user = getUser(&m).pointee
            users[user.nUserID] = user
            
            if currentCmdId == 0 && user.nChannelID == curchannel.nChannelID {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_USER_LOGGEDOUT :
            let user = getUser(&m).pointee
            users.removeValue(forKey: user.nUserID)

            if currentCmdId == 0 && user.nChannelID == curchannel.nChannelID {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_USER_JOINED :
            let user = getUser(&m).pointee
            users[user.nUserID] = user
            
            // we joined a new channel so update table view
            if user.nUserID == TT_GetMyUserID(ttInst) {
                curchannel = channels[user.nChannelID]!
                mychannel = channels[user.nChannelID]!
                
                //store password if it's from initial login (Server-struct)
                if rejoinchannel.nChannelID == 0 && chanpasswds[user.nChannelID] == nil {
                   chanpasswds[user.nChannelID] = fromTTString(rejoinchannel.szPassword)
                }
                rejoinchannel = channels[user.nChannelID]! //join this on connection lost

                updateTitle()
            }
            if user.nChannelID == mychannel.nChannelID && mychannel.nChannelID > 0 {
                playSound(.joined_CHAN)
                let defaults = UserDefaults.standard
                
                if defaults.object(forKey: PREF_TTSEVENT_JOINEDCHAN) == nil || defaults.bool(forKey: PREF_TTSEVENT_JOINEDCHAN) {
                    let name = getDisplayName(user)
                    newUtterance(name + " " +  NSLocalizedString("has joined the channel", comment: "TTS EVENT"))
                }
            }

            if currentCmdId == 0 {
                self.tableView.reloadData()
            }
        case CLIENTEVENT_CMD_USER_UPDATE :
            let user = getUser(&m).pointee
            users[user.nUserID] = user
            
            if currentCmdId == 0 {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_USER_LEFT :
            let user = getUser(&m).pointee
            users[user.nUserID] = user
            
            if myuseraccount.uUserRights & USERRIGHT_VIEW_ALL_USERS.rawValue == 0 {
                users.removeValue(forKey: user.nUserID)
            }
            else {
                users[user.nUserID] = user
            }
    
            if user.nUserID == TT_GetMyUserID(ttInst) {
                mychannel = Channel()
                rejoinchannel = Channel()
            }
            
            if m.nSource == mychannel.nChannelID && mychannel.nChannelID > 0 {
                playSound(.left_CHAN)
                let defaults = UserDefaults.standard
                if defaults.object(forKey: PREF_TTSEVENT_LEFTCHAN) == nil || defaults.bool(forKey: PREF_TTSEVENT_LEFTCHAN) {
                    let name = getDisplayName(user)
                    newUtterance(name + " " + NSLocalizedString("has left the channel", comment: "TTS EVENT"))
                }
            }
            
            if currentCmdId == 0 {
                self.tableView.reloadData()
            }
            
        case CLIENTEVENT_CMD_USER_TEXTMSG :
            let txtmsg = getTextMessage(&m).pointee
            
            if txtmsg.nMsgType == MSGTYPE_USER {
                
                let settings = UserDefaults.standard
                if let user = users[txtmsg.nFromUserID] {
                    let name = getDisplayName(user)
                    let newmsg = MyTextMessage(m: txtmsg, nickname: name,
                        msgtype: TT_GetMyUserID(ttInst) == txtmsg.nFromUserID ? .im_MYSELF : .im)
                    appendTextMessage(txtmsg.nFromUserID, txtmsg: newmsg)
                    
                    if unreadmessages.count == 0 {
                        unreadTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(ChannelListViewController.timerUnread), userInfo: nil, repeats: true)
                    }
                    unreadmessages.insert(txtmsg.nFromUserID)                    
                }
                
                //ignore incoming message if text message view controller is already open
                if self.navigationController?.topViewController is TextMessageViewController {
                    let vc = self.navigationController?.topViewController as! TextMessageViewController
                    if vc.userid == txtmsg.nFromUserID {
                        break
                    }
                }
                
                if settings.object(forKey: PREF_DISPLAY_POPUPTXTMSG) == nil || settings.bool(forKey: PREF_DISPLAY_POPUPTXTMSG) {
                    let vc = self.storyboard?.instantiateViewController(withIdentifier: "Text Message") as! TextMessageViewController
                    openTextMessages(vc, userid: txtmsg.nFromUserID)
                    self.navigationController?.pushViewController(vc, animated: true)
                    if vc.messages.count > 0 {
                        speakTextMessage(txtmsg.nMsgType, mymsg: vc.messages.last!)
                    }
                }
            }
            
        case CLIENTEVENT_CMD_ERROR :
            if m.nSource == cmdid {
                let errmsg = getClientErrorMsg(&m).pointee
                let s = fromTTString(errmsg.szErrorMsg)
                if #available(iOS 8.0, *) {
                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "Dialog message"), message: s, preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Dialog message"), style: UIAlertActionStyle.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                } else {
                    // Fallback on earlier versions
                }
            }

        case CLIENTEVENT_USER_STATECHANGE :
            let user = getUser(&m).pointee
            users[user.nUserID] = user
            self.tableView.reloadData()
        
        case CLIENTEVENT_VOICE_ACTIVATION :
            
            tableView.reloadData()

        default :
            //print("Unhandled message \(m.nClientEvent.rawValue)")
            break
        }

    }
}
