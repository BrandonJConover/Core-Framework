// Connecting, logging in and registering: mudclient_login / mudclient_register
// / mudclient_reset_game and friends from rsc-c's mudclient.c.

import Foundation

extension Mudclient {
    /// packet_stream_new: opens a socket to the selected world.
    func openPacketStream() -> PacketStream? {
        packetStream?.close()
        packetStream = nil
        guard let rsa = RSA(exponentHex: rsaExponent, modulusHex: rsaModulus),
              let transport = try? SocketTransport(host: server, port: port) else { return nil }
        let ps = PacketStream(transport: transport, rsa: rsa)
        packetStream = ps
        return ps
    }

    private func isaacKeys(_ sessionId: Int64) -> [UInt32] {
        let r = CRandom.shared
        let k0 = Int32(Float(r.next()) / Float(Int32.max) * 99_999_999)
        let k1 = Int32(Float(r.next()) / Float(Int32.max) * 99_999_999)
        return [UInt32(bitPattern: k0), UInt32(bitPattern: k1), UInt32(truncatingIfNeeded: sessionId >> 32),
                UInt32(truncatingIfNeeded: sessionId)]
    }

    /// Sends CLIENT_SESSION and reads the session id. Returns nil if the connection failed.
    private func requestSession(_ formattedUsername: String) -> (PacketStream, Int64)? {
        guard let ps = openPacketStream(), !ps.closed else { return nil }
        ps.newPacket(ClientOpcode.session)
        let encoded = ClientUtil.encodeUsername(formattedUsername)
        ps.putByte(Int((encoded >> 16) & 31))
        if ps.flushPacket() < 0 { return nil }
        return (ps, ps.getLong())
    }

    public func login(username: String, password: String, reconnecting: Bool) {
        if worldFullTimeout > 0 {
            showLoginScreenStatus("Please wait...", "Connecting to server")
            Thread.sleep(forTimeInterval: 2)
            showLoginScreenStatus("Sorry! the server is currently full.", "Please try again later")
            return
        }
        if username.isEmpty || password.isEmpty {
            showLoginScreenStatus("You must enter both a username", "and a password - Please try again")
            return
        }
        self.username = username
        self.password = password
        let user = ClientUtil.formatAuthString(username, Mudclient.usernameLength)
        let pass = ClientUtil.formatAuthString(password, Mudclient.passwordLength)
        if reconnecting {
            drawLostConnection()
            draw()
        } else {
            showLoginScreenStatus("Please wait...", "Connecting to server")
        }

        guard let (ps, session) = requestSession(user) else { return loginFailed(username, password, reconnecting) }
        sessionId = session
        if sessionId == 0 {
            showLoginScreenStatus("Login server offline.", "Please try again in a few mins")
            return
        }
        ps.newPacket(ClientOpcode.login)
        ps.putByte(reconnecting ? 1 : 0)
        ps.putShort(Mudclient.version)
        ps.putByte(0)
        ps.putLoginBlock(username: user, password: pass, isaacKeys: isaacKeys(session), uuid: 0)
        if ps.flushPacket() < 0 { return loginFailed(username, password, reconnecting) }
        let response = ps.getByte()

        if response == 0 || response == 1 || response == 25 {
            moderatorLevel = response == 25 ? 1 : 0
            autoLoginAttempts = 0
            options.username = options.rememberUsername != 0 ? username : ""
            options.password = options.rememberPassword != 0 ? password : ""
            if options.rememberUsername != 0 || options.rememberPassword != 0 { options.save() }
            resetGame()
            return
        }
        if reconnecting {
            resetLoginScreen()
            return
        }
        let messages: [Int: (String, String)] = [
            -1: ("Error unable to login.", "Server timed out"),
            3: ("Invalid username or password.", "Try again, or create a new account"),
            4: ("That username is already logged in.", "Wait 60 seconds then retry"),
            5: ("The client has been updated.", "Please reload this page"),
            6: ("You may only use 1 character at once.", "Your ip-address is already in use"),
            7: ("Login attempts exceeded!", "Please try again in 5 minutes"),
            8: ("Error unable to login.", "Server rejected session"),
            9: ("Error unable to login.", "Loginserver rejected session"),
            10: ("That username is already in use.", "Wait 60 seconds then retry"),
            11: ("Account temporarily disabled.", "Check your message inbox for details"),
            12: ("Account permanently disabled.", "Check your message inbox for details"),
            14: ("Sorry! This world is currently full.", "Please try a different world"),
            15: ("You need a members account", "to login to this world"),
            16: ("Error - no reply from loginserver.", "Please try again"),
            17: ("Error - failed to decode profile.", "Contact customer support"),
            18: ("Account suspected stolen.", "Press \"recover a locked account\" on front page."),
            20: ("Error - loginserver mismatch", "Please try a different world"),
            21: ("Unable to login.", "That is not an RS-Classic account"),
            22: ("Password suspected stolen.", "Press \"change your password\" on front page."),
        ]
        let (a, b) = messages[response] ?? ("Error unable to login.", "Unrecognised response code")
        showLoginScreenStatus(a, b)
        if response == 14 { worldFullTimeout = 1500 }
    }

    private func loginFailed(_ username: String, _ password: String, _ reconnecting: Bool) {
        if autoLoginAttempts > 0 {
            Thread.sleep(forTimeInterval: 5)
            autoLoginAttempts -= 1
            login(username: username, password: password, reconnecting: reconnecting)
            return
        }
        if reconnecting {
            resetLoginScreen()
            loginScreen = .existing
        }
        showLoginScreenStatus("Sorry! Unable to connect.", "Check internet settings or try another world")
    }

    public func registrationLogin() {
        let user = panelLoginNewUser.text(controlRegisterUser)
        let pass = panelLoginNewUser.text(controlRegisterPassword)
        loginScreen = .existing
        panelLoginExistingUser.updateText(controlLoginStatus, "Please enter your username and password")
        panelLoginExistingUser.updateText(controlLoginUsername, user)
        panelLoginExistingUser.updateText(controlLoginPassword, pass)
        drawLoginScreens()
        resetTimings()
        login(username: user, password: pass, reconnecting: false)
    }

    public func register(username: String, password: String) {
        if worldFullTimeout > 0 {
            showLoginScreenStatus("Please wait...", "Connecting to server")
            Thread.sleep(forTimeInterval: 2)
            showLoginScreenStatus("Sorry! The server is currently full.", "Please try again later")
            return
        }
        let user = ClientUtil.formatAuthString(username, Mudclient.usernameLength)
        let pass = ClientUtil.formatAuthString(password, Mudclient.passwordLength)
        showLoginScreenStatus("Please wait...", "Connecting to server")
        let failed = { self.showLoginScreenStatus("Sorry! Unable to connect.", "Check internet settings or try another world") }
        guard let (ps, session) = requestSession(user) else { return failed() }
        sessionId = session
        if sessionId == 0 {
            showLoginScreenStatus("Login server offline.", "Please try again in a few mins")
            return
        }
        ps.newPacket(ClientOpcode.register)
        ps.putByte(0)
        ps.putShort(Mudclient.version)
        ps.putByte(0)
        ps.putLoginBlock(username: user, password: pass, isaacKeys: isaacKeys(session), uuid: 0)
        if ps.flushPacket() < 0 { return failed() }
        let response = ps.getByte()
        switch response {
        case 2: registrationLogin()
        case 13, 3: showLoginScreenStatus("Username already taken.", "Please choose another username")
        case 4: showLoginScreenStatus("That username is already in use.", "Wait 60 seconds then retry")
        case 5: showLoginScreenStatus("The client has been updated.", "Please reload this page")
        case 6: showLoginScreenStatus("You may only use 1 character at once.", "Your ip-address is already in use")
        case 7: showLoginScreenStatus("Login attempts exceeded!", "Please try again in 5 minutes")
        case 11: showLoginScreenStatus("Account has been temporarily disabled", "for cheating or abuse")
        case 12: showLoginScreenStatus("Account has been permanently disabled", "for cheating or abuse")
        case 14:
            showLoginScreenStatus("Sorry! The server is currently full.", "Please try again later")
            worldFullTimeout = 1500
        case 15: showLoginScreenStatus("You need a members account", "to login to this server")
        case 16: showLoginScreenStatus("Please login to a members server", "to access member-only features")
        default: showLoginScreenStatus("Error unable to create username.", "Unrecognised response code")
        }
    }

    /// mudclient_change_password: rsc-c sends an empty packet (the passwords are never written).
    public func changePassword(old: String, new: String) {
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.changePassword)
        _ = ps.flushPacket()
    }

    public func resetGame() {
        systemUpdate = 0
        combatStyle = 0
        logoutTimeout = 0
        loginScreen = .welcome
        loggedIn = true
        inputPmCurrent = ""
        inputPmFinal = ""
        surface.blackScreen()
        draw()
        for i in 0..<objectCount {
            if let m = objects[i].model { scene.removeModel(m) }
            world.removeObject(x: objects[i].x, y: objects[i].y, id: objects[i].id)
            objects[i].model = nil
        }
        for i in 0..<wallObjectCount {
            if let m = wallObjects[i].model { scene.removeModel(m) }
            world.removeWallObject(x: wallObjects[i].x, y: wallObjects[i].y, dir: wallObjects[i].direction,
                                   id: wallObjects[i].id)
            wallObjects[i].model = nil
        }
        objectCount = 0
        wallObjectCount = 0
        groundItemCount = 0
        playerCount = 0
        for i in 0..<Mudclient.playersServerMax { playerServer[i] = nil }
        for i in 0..<Mudclient.playersMax { players[i] = nil }
        combatTarget = nil
        localPlayer = GameCharacter()
        npcCount = 0
        for i in 0..<Mudclient.npcsServerMax { npcsServer[i] = nil }
        for i in 0..<Mudclient.npcsMax { npcs[i] = nil }
        for i in 0..<Mudclient.prayerCount { prayerOn[i] = false }
        mouseButtonClick = 0
        lastMouseButtonDown = 0
        mouseButtonDown = 0
        showDialogShop = false
        showDialogBank = false
        isSleeping = false
        friendListCount = 0
    }

    public func closeConnection() {
        if let ps = packetStream {
            ps.newPacket(ClientOpcode.closeConnection)
            _ = ps.flushPacket()
        }
        username = ""
        password = ""
        resetLoginScreen()
    }

    public func lostConnection() {
        systemUpdate = 0
        if logoutTimeout != 0 {
            resetLoginScreen()
        } else {
            autoLoginAttempts = 10
            login(username: username, password: password, reconnecting: true)
        }
    }

    public func sendLogout() {
        if !loggedIn { return }
        if combatTimeout > 450 {
            showMessage("@cya@You can't logout during combat!", .game)
            return
        }
        if combatTimeout > 0 {
            showMessage("@cya@You can't logout for 10 seconds after combat", .game)
            return
        }
        guard let ps = packetStream else { return }
        ps.newPacket(ClientOpcode.logout)
        ps.sendPacket()
        logoutTimeout = 1000
    }

    // MARK: - ui/lost-connection.c, ui/logout.c

    public func drawLostConnection() {
        let w = 280, h = 50
        let x = surface.width / 2 - w / 2
        let y = surface.height / 2 - h / 2 - 1
        surface.drawBox(x: x, y: y, width: w, height: h, colour: Colour.black)
        surface.drawBorder(x: x, y: y, width: w, height: h, colour: Colour.white)
        surface.drawStringCentre("Connection lost! Please wait...", x: surface.width / 2, y: surface.height / 2 - 5,
                                 font: .bold14, colour: Colour.white)
        surface.drawStringCentre("Attempting to re-establish", x: surface.width / 2, y: surface.height / 2 + 13,
                                 font: .bold14, colour: Colour.white)
    }

    public func drawLogout() {
        let w = 260, h = 60
        let x = surface.width / 2 - w / 2
        let y = (surface.height - 12) / 2 - h / 2
        surface.drawBox(x: x, y: y, width: w, height: h, colour: Colour.black)
        surface.drawBorder(x: x, y: y, width: w, height: h, colour: Colour.white)
        surface.drawStringCentre("Logging out...", x: surface.width / 2, y: surface.height / 2, font: .bold16,
                                 colour: Colour.white)
    }

    public func updateBankItems() {
        bankItemCount = newBankItemCount
        for i in 0..<newBankItemCount {
            bankItems[i] = newBankItems[i]
            bankItemsCount[i] = newBankItemsCount[i]
        }
        for i in 0..<inventoryItemsCount {
            if bankItemCount >= bankItemsMax { break }
            let id = inventoryItemId[i]
            if !bankItems[0..<bankItemCount].contains(id) {
                bankItems[bankItemCount] = id
                bankItemsCount[bankItemCount] = 0
                bankItemCount += 1
            }
        }
    }
}
