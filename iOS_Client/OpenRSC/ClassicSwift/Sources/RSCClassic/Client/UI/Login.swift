// Login screens: port of rsc-c's ui/login.c and ui/worldlist.c.

import Foundation

public struct WorldEntry {
    public var name: String
    public var host: String
    public var port: Int
    public var rsaExponent: String
    public var rsaModulus: String

    public static let defaults: [WorldEntry] = [
        WorldEntry(name: "OpenRSC_Preservation", host: "game.openrsc.com", port: 43596, rsaExponent: "00010001",
                   rsaModulus: "87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25"),
        WorldEntry(name: "OpenRSC_Uranium", host: "game.openrsc.com", port: 43235, rsaExponent: "00010001",
                   rsaModulus: "87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25"),
        WorldEntry(name: "Neat_F2P", host: "192.3.118.9", port: 43594, rsaExponent: "00010001",
                   rsaModulus: "86b03ac30518bdb3e508ca9660efc7738a73ee7dbedbcebf8c56d030a2bdae70503c60829b7fb5eceb529442234c21bce6d529c8da4fce870e83ceffc379e281"),
        WorldEntry(name: "localhost", host: "localhost", port: 43594,
                   rsaExponent: "81f390b2cf8ca7039ee507975951d5a0b15a87bf8b3f99c966834118c50fd94d",
                   rsaModulus: "88c38748a58228f7261cdc340b5691d7d0975dee0ecdb717609e6bf971eb3fe723ef9d130e4686813739768ad9472eb46d8bfcc042c1a5fcb05e931f632eea5d"),
    ]

    /// worlds.cfg: "name host port exponent modulus" per line.
    public static func parse(_ text: String) -> [WorldEntry] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 5, let port = Int(f[2]) else { return nil }
            return WorldEntry(name: String(f[0].prefix(30)), host: String(f[1].prefix(60)), port: port,
                              rsaExponent: f[3], rsaModulus: f[4])
        }
    }
}

extension Mudclient {
    var loginBackgroundHeight: Int { isCompact ? 125 : 200 }

    // MARK: - ui/login.c

    public func createLoginPanels() {
        let compact = isCompact
        let touch = isTouchLayout
        let bgHeight = loginBackgroundHeight
        panelLoginWelcome = makePanel(50)
        let p = panelLoginWelcome!
        let x = (compact ? Mudclient.minWidth : Mudclient.vanillaWidth) / 2
        var y = 40
        let offsetY = compact ? 17 : 40
        let showRegistration = options.members == 0 || options.registration != 0

        if showRegistration {
            let offsetX = compact ? 16 : 0
            p.addTextCentre(x: x, y: bgHeight + y - (compact ? 20 : 0), text: touch ? "Tap an option" : "Click on an option",
                            font: .bold16, alternativeColour: true)
            p.addButtonBackground(x: x - 100 + offsetX, y: bgHeight + offsetY + y, width: 120, height: 35)
            p.addTextCentre(x: x - 100 + offsetX, y: bgHeight + offsetY + y, text: "New User", font: .bold16,
                            alternativeColour: false)
            controlWelcomeNewUser = p.addButton(x: x - 100 + offsetX, y: bgHeight + offsetY + y, width: 120, height: 35)
            p.addButtonBackground(x: x + 100 - offsetX, y: bgHeight + offsetY + y, width: 120, height: 35)
            p.addTextCentre(x: x + 100 - offsetX, y: bgHeight + offsetY + y, text: "Existing User", font: .bold16,
                            alternativeColour: false)
            controlWelcomeExistingUser = p.addButton(x: x + 100 - offsetX, y: bgHeight + offsetY + y, width: 120,
                                                     height: 35)
        } else {
            var font = FontStyle.bold14
            var buttonWidth = 200
            if compact {
                y -= 18
                font = .bold13
                buttonWidth = 180
            }
            p.addTextCentre(x: x, y: bgHeight + y, text: "Welcome to RuneScape", font: font, alternativeColour: true)
            p.addTextCentre(x: x, y: bgHeight + 15 + y, text: "You need a members account to use this server",
                            font: font, alternativeColour: true)
            p.addButtonBackground(x: x, y: bgHeight + 50 + y, width: buttonWidth, height: 35)
            p.addTextCentre(x: x, y: bgHeight + 50 + y, text: touch ? "Tap here to login" : "Click here to login",
                            font: .bold16, alternativeColour: false)
            controlWelcomeExistingUser = p.addButton(x: x, y: bgHeight + 50 + y, width: buttonWidth, height: 35)
        }

        if options.showAdditionalOptions != 0 {
            var buttonX = (compact ? Mudclient.minWidth : Mudclient.vanillaWidth) - 36
            let buttonY = compact ? Mudclient.minHeight - 24 : Mudclient.vanillaHeight - 32
            p.addButtonBackground(x: buttonX, y: buttonY, width: 60, height: 20)
            p.addTextCentre(x: buttonX, y: buttonY, text: "Options", font: .bold12, alternativeColour: false)
            controlWelcomeOptions = p.addButton(x: buttonX, y: buttonY, width: 60, height: 20)
            buttonX -= 63
            p.addButtonBackground(x: buttonX, y: buttonY, width: 60, height: 20)
            p.addTextCentre(x: buttonX, y: buttonY, text: "Worlds", font: .bold12, alternativeColour: false)
            controlWelcomeWorlds = p.addButton(x: buttonX, y: buttonY, width: 60, height: 20)
        }

        panelLoginNewUser = makePanel(50)
        let n = panelLoginNewUser!
        if options.accountManagement == 0 {
            let font: FontStyle = compact ? .regular12 : .bold14
            y = compact ? 140 : 230
            if referId == 0 && !compact {
                n.addTextCentre(x: x, y: y + 8, text: "To create an account please go back to the", font: font,
                                alternativeColour: true)
                y += 20
                n.addTextCentre(x: x, y: y + 8, text: "www.runescape.com front page, and choose 'create account'",
                                font: font, alternativeColour: true)
            } else if referId == 1 {
                n.addTextCentre(x: x, y: y + 8, text: "To create an account please click on the", font: font,
                                alternativeColour: true)
                y += 20
                n.addTextCentre(x: x, y: y + 8, text: "'create account' link below the game window", font: font,
                                alternativeColour: true)
            } else {
                n.addTextCentre(x: x, y: y + 8, text: "To create an account please go back to the", font: font,
                                alternativeColour: true)
                y += 20
                n.addTextCentre(x: x, y: y + 8, text: "runescape front webpage and choose 'create account'",
                                font: font, alternativeColour: true)
            }
            y += 30
            n.addButtonBackground(x: x, y: y + 17, width: 150, height: 34)
            n.addTextCentre(x: x, y: y + 17, text: "Ok", font: .bold16, alternativeColour: false)
            controlLoginNewOk = n.addButton(x: x, y: y + 17, width: 150, height: 34)
        } else {
            if compact {
                y = 12
                controlRegisterStatus = n.addTextCentre(x: x, y: y + 8, text: "To create an account please enter",
                                                        font: .bold13, alternativeColour: true)
                y += 13
                controlRegisterStatusBottom = n.addTextCentre(x: x, y: y + 8, text: "all the requested details",
                                                              font: .bold13, alternativeColour: true)
            } else {
                y = 70
                controlRegisterStatus = n.addTextCentre(
                    x: x, y: y + 8, text: "To create an account please enter all the requested details",
                    font: .bold14, alternativeColour: true)
            }
            var oy = y + 25
            n.addButtonBackground(x: x, y: oy + 17, width: 250, height: 34)
            n.addTextCentre(x: x, y: oy + 8, text: "Choose a username", font: .bold14, alternativeColour: false)
            controlRegisterUser = n.addTextInput(x: x, y: oy + 25, width: 200, height: 40, font: .bold14, maxLength: 12,
                                                 isPassword: false, alternativeColour: false)
            oy += 40
            if compact {
                n.addButtonBackground(x: x, y: oy + 17, width: 220, height: 34)
                n.addTextCentre(x: x, y: oy + 8, text: "Choose a Password", font: .bold14, alternativeColour: false)
                controlRegisterPassword = n.addTextInput(x: x, y: oy + 25, width: 220, height: 40, font: .bold14,
                                                         maxLength: 20, isPassword: true, alternativeColour: false)
                oy += 40
                n.addButtonBackground(x: x, y: oy + 17, width: 220, height: 34)
                n.addTextCentre(x: x, y: oy + 8, text: "Confirm Password", font: .bold14, alternativeColour: false)
                controlRegisterConfirmPassword = n.addTextInput(x: x, y: oy + 25, width: 220, height: 40, font: .bold14,
                                                                maxLength: 20, isPassword: true, alternativeColour: false)
                oy += 34
            } else {
                n.addButtonBackground(x: x - 115, y: oy + 17, width: 220, height: 34)
                n.addTextCentre(x: x - 115, y: oy + 8, text: "Choose a Password", font: .bold14, alternativeColour: false)
                controlRegisterPassword = n.addTextInput(x: x - 115, y: oy + 25, width: 220, height: 40, font: .bold14,
                                                         maxLength: 20, isPassword: true, alternativeColour: false)
                n.addButtonBackground(x: x + 115, y: oy + 17, width: 220, height: 34)
                n.addTextCentre(x: x + 115, y: oy + 8, text: "Confirm Password", font: .bold14, alternativeColour: false)
                controlRegisterConfirmPassword = n.addTextInput(x: x + 115, y: oy + 25, width: 220, height: 40,
                                                                font: .bold14, maxLength: 20, isPassword: true,
                                                                alternativeColour: false)
                oy += 60
                controlRegisterCheckbox = n.addCheckbox(x: x - 196 - 7, y: oy - 7, width: 14, height: 14)
                n.addText(x: x - 181, y: oy, text: "I have read and agreed to the terms and conditions", font: .bold14,
                          alternativeColour: true)
                oy += 15
                n.addTextCentre(x: x, y: oy, text: "(to view these click the relevant link below this game window)",
                                font: .bold14, alternativeColour: true)
            }
            oy += 20
            let offsetX = compact ? 20 : 0
            n.addButtonBackground(x: x - 100 + offsetX, y: oy + 17, width: 150, height: 34)
            n.addTextCentre(x: x - 100 + offsetX, y: oy + 17, text: "Submit", font: .bold16, alternativeColour: false)
            controlRegisterSubmit = n.addButton(x: x - 100 + offsetX, y: oy + 17, width: 150, height: 34)
            n.addButtonBackground(x: x + 100 - offsetX, y: oy + 17, width: 150, height: 34)
            n.addTextCentre(x: x + 100 - offsetX, y: oy + 17, text: "Cancel", font: .bold16, alternativeColour: false)
            controlRegisterCancel = n.addButton(x: x + 100 - offsetX, y: oy + 17, width: 150, height: 34)
        }

        panelLoginExistingUser = makePanel(50)
        let e = panelLoginExistingUser!
        y = bgHeight + 30
        if compact {
            y -= 34
            controlLoginStatus = e.addTextCentre(x: x, y: y - 10, text: "", font: .bold13, alternativeColour: true)
            y += 13
            controlLoginStatusBottom = e.addTextCentre(x: x, y: y - 10, text: "Please enter your username and password",
                                                       font: .bold13, alternativeColour: true)
            y += 24
            e.addButtonBackground(x: x - 56, y: y, width: 200, height: 40)
            e.addTextCentre(x: x - 56, y: y - 10, text: "Username:", font: .bold14, alternativeColour: false)
            controlLoginUsername = e.addTextInput(x: x - 56, y: y + 10, width: 200, height: 40, font: .bold14,
                                                  maxLength: 12, isPassword: false, alternativeColour: false)
            y += 47
            e.addButtonBackground(x: x - 32, y: y, width: 200, height: 40)
            e.addTextCentre(x: x - 32, y: y - 10, text: "Password:", font: .bold14, alternativeColour: false)
            controlLoginPassword = e.addTextInput(x: x - 32, y: y + 10, width: 200, height: 40, font: .bold14,
                                                  maxLength: 20, isPassword: true, alternativeColour: false)
            y -= 55
            e.addButtonBackground(x: x + 154 - 38, y: y, width: 80, height: 25)
            e.addTextCentre(x: x + 154 - 38, y: y, text: "Ok", font: .bold14, alternativeColour: false)
            controlLoginOk = e.addButton(x: x + 154 - 38, y: y, width: 80, height: 25)
            y += 30
            e.addButtonBackground(x: x + 154 - 38, y: y, width: 80, height: 25)
            e.addTextCentre(x: x + 154 - 38, y: y, text: "Cancel", font: .bold14, alternativeColour: false)
            controlLoginCancel = e.addButton(x: x + 154 - 38, y: y, width: 80, height: 25)
        } else {
            controlLoginStatus = e.addTextCentre(x: x, y: y - 10, text: "Please enter your username and password",
                                                 font: .bold14, alternativeColour: true)
            y += 28
            e.addButtonBackground(x: x - 116, y: y, width: 200, height: 40)
            e.addTextCentre(x: x - 116, y: y - 10, text: "Username:", font: .bold14, alternativeColour: false)
            controlLoginUsername = e.addTextInput(x: x - 116, y: y + 10, width: 200, height: 40, font: .bold14,
                                                  maxLength: 12, isPassword: false, alternativeColour: false)
            y += 47
            e.addButtonBackground(x: x - 66, y: y, width: 200, height: 40)
            e.addTextCentre(x: x - 66, y: y - 10, text: "Password:", font: .bold14, alternativeColour: false)
            controlLoginPassword = e.addTextInput(x: x - 66, y: y + 10, width: 200, height: 40, font: .bold14,
                                                  maxLength: 20, isPassword: true, alternativeColour: false)
            y -= 55
            e.addButtonBackground(x: x + 154, y: y, width: 120, height: 25)
            e.addTextCentre(x: x + 154, y: y, text: "Ok", font: .bold14, alternativeColour: false)
            controlLoginOk = e.addButton(x: x + 154, y: y, width: 120, height: 25)
            y += 30
            e.addButtonBackground(x: x + 154, y: y, width: 120, height: 25)
            e.addTextCentre(x: x + 154, y: y, text: "Cancel", font: .bold14, alternativeColour: false)
            controlLoginCancel = e.addButton(x: x + 154, y: y, width: 120, height: 25)
        }
    }

    public func showLoginScreenStatus(_ s: String, _ s1: String) {
        let compact = isCompact
        if loginScreen == .new {
            loginScreenStatus = "\(s) \(s1)"
            if compact {
                panelLoginNewUser.updateText(controlRegisterStatus, s)
                panelLoginNewUser.updateText(controlRegisterStatusBottom, s1)
            } else {
                panelLoginNewUser.updateText(controlRegisterStatus, loginScreenStatus)
            }
        } else if loginScreen == .existing {
            if compact {
                panelLoginExistingUser.updateText(controlLoginStatus, s)
                panelLoginExistingUser.updateText(controlLoginStatusBottom, s1)
            } else {
                loginScreenStatus = "\(s) \(s1)"
                panelLoginExistingUser.updateText(controlLoginStatus, loginScreenStatus)
            }
        }
        drawLoginScreens()
        resetTimings()
    }

    public func resetLoginScreen() {
        loggedIn = false
        loginScreen = .welcome
        loginUsername = ""
        loginPass = ""
        loginPrompt = "Please enter a username:"
        loginUsernameDisplay = "*\(loginUsername)*"
        playerCount = 0
        npcCount = 0
    }

    /// mudclient_render_login_scene_sprites: renders the three login backgrounds into sprite_logo..+2.
    public func renderLoginSceneSprites() {
        let bgHeight = loginBackgroundHeight
        world.loadSection(x: 50 * 48 + 23, y: 50 * 48 + 23, plane: 0)
        world.addModels(gameModels.map { $0 ?? GameModel(vertices: 1, faces: 1) })
        scene.clipFar3d = 4100
        scene.clipFar2d = 4100
        scene.fogZDistance = 4000

        let logoWidth = Mudclient.width - 29
        let logoHeight = Int(Float(logoWidth) / 483.0 * 146.0)
        let offsetX = surface.width / 2 - logoWidth / 2
        let offsetY = 15

        func capture(_ x: Int, _ y: Int, _ zoom: Int, _ rotation: Int, _ sprite: Int) {
            surface.blackScreen()
            scene.setCamera(x: x, y: -world.elevation(x, y), z: y, yaw: 912, pitch: rotation, roll: 0,
                            distance: zoom * 2)
            scene.render()
            surface.applyLoginFilter(backgroundHeight: bgHeight)
            surface.drawSpriteTransformMask(x: offsetX, y: offsetY, width: logoWidth, height: logoHeight,
                                            id: spriteMedia + 10, maskColour: 0, skinColour: 0, skewX: 0, flip: false)
            surface.screenRasterToSprite(id: sprite, x: 0, y: 0, width: surface.width, height: bgHeight)
            surface.screenRasterToPaletteSprite(id: sprite)
            surface.loadSprite(id: sprite)
        }

        capture(9728, 6400, 1100, 888, spriteLogo)
        capture(9216, 9216, 1100, 888, spriteLogo + 1)

        for i in 0..<World.terrainCount {
            for m in [world.roofModels[0][i], world.wallModels[1][i], world.roofModels[1][i],
                      world.wallModels[2][i], world.roofModels[2][i]] {
                if let m { scene.removeModel(m) }
            }
            world.roofModels[0][i] = nil
            world.wallModels[1][i] = nil
            world.roofModels[1][i] = nil
            world.wallModels[2][i] = nil
            world.roofModels[2][i] = nil
        }

        capture(11136, 10368, 500, 376, spriteLogo + 2)

        world.reset(dispose: false)
        for i in 0..<scene.modelCount { scene.models[i] = nil }
        scene.modelCount = 0
    }

    public func drawLoginScreens() {
        let compact = isCompact
        let bgWidth = compact ? Mudclient.minWidth : Mudclient.vanillaWidth
        let bgHeight = loginBackgroundHeight
        welcomeScreenAlreadyShown = false
        surface.interlace = false
        surface.blackScreen()

        var showBackground = loginScreen != .recover && loginScreen != .new
        if loginScreen == .new && options.accountManagement == 0 { showBackground = true }
        if options.lowmem != 0 { showBackground = false }

        if showBackground {
            let width = compact ? Mudclient.minWidth : Mudclient.vanillaWidth
            let height = compact ? Mudclient.minHeight : Mudclient.vanillaHeight
            let offsetX = surface.width / 2 - width / 2
            let offsetY = surface.height / 2 - height / 2
            var cycle = (loginTimer * 2) % 3072
            let scaleLogin = bgHeight != surface.spriteHeight[spriteLogo]
            let spriteOffset = cycle / 1024
            cycle %= 1024
            if scaleLogin {
                surface.drawSpriteScale(x: offsetX, y: offsetY + 10, width: bgWidth, height: bgHeight,
                                        id: spriteLogo + spriteOffset)
            } else {
                surface.drawSprite(x: offsetX, y: offsetY + 10, id: spriteLogo + spriteOffset)
            }
            if cycle > 768 {
                let next = spriteLogo + (spriteOffset == 2 ? 0 : spriteOffset + 1)
                let alpha = cycle - 768
                if scaleLogin {
                    surface.drawSpriteScaleAlpha(x: offsetX, y: offsetY + 10, width: bgWidth, height: bgHeight,
                                                 id: next, alpha: alpha)
                } else {
                    surface.drawSpriteAlpha(x: offsetX, y: offsetY + 10, id: next, alpha: alpha)
                }
            }
            if offsetX > 0 {
                for i in 0..<3 {
                    let alpha = 192 - i * 64
                    surface.drawBoxAlpha(x: i * 2 + offsetX, y: offsetY + 10, width: 2, height: bgHeight,
                                         colour: Colour.black, alpha: alpha)
                    surface.drawBoxAlpha(x: bgWidth - i * 2 + offsetX, y: 10 + offsetY, width: 2, height: bgHeight,
                                         colour: Colour.black, alpha: alpha)
                }
            }
        }

        switch loginScreen {
        case .welcome: panelLoginWelcome.drawPanel()
        case .new: panelLoginNewUser.drawPanel()
        case .existing:
            if compact {
                var boxHeight = 12
                if !panelLoginExistingUser.controlText[controlLoginStatus].isEmpty { boxHeight *= 2 }
                surface.drawBoxAlpha(x: 0, y: bgHeight - boxHeight + (surface.height / 2 - Mudclient.minHeight / 2),
                                     width: surface.width, height: boxHeight + 4, colour: 0, alpha: 128)
            }
            panelLoginExistingUser.drawPanel()
        case .recover: break
        case .world: panelLoginWorldlist.drawPanel()
        }

        if options.lowmem == 0 { drawBlueBar() }
        if showAdditionalOptions {
            drawAdditionalOptions()
            if showDialogConfirm { drawConfirm() }
        }
        draw()
    }

    public func handleLoginScreenInput() {
        let compact = isCompact
        if showDialogConfirm { handleConfirmInput(); return }
        if showAdditionalOptions { handleAdditionalOptionsInput(); return }
        if worldFullTimeout > 0 { worldFullTimeout -= 1 }

        switch loginScreen {
        case .welcome:
            let p = panelLoginWelcome!
            p.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                          scrollDelta: mouseScrollDelta)
            if p.isClicked(controlWelcomeNewUser) {
                loginScreen = .new
                if options.accountManagement != 0 {
                    let n = panelLoginNewUser!
                    n.updateText(controlRegisterUser, "")
                    n.updateText(controlRegisterPassword, "")
                    n.updateText(controlRegisterConfirmPassword, "")
                    n.setFocus(controlRegisterUser)
                    if compact {
                        n.updateText(controlRegisterStatus, "To create an account please enter")
                        n.updateText(controlRegisterStatusBottom, "all the requested details")
                        n.toggleCheckbox(controlRegisterCheckbox, activated: true)
                    } else {
                        n.updateText(controlRegisterStatus, "To create an account please enter all the requested details")
                        n.toggleCheckbox(controlRegisterCheckbox, activated: false)
                    }
                }
            } else if p.isClicked(controlWelcomeExistingUser) {
                loginScreen = .existing
                let e = panelLoginExistingUser!
                if compact {
                    e.updateText(controlLoginStatus, "")
                    e.updateText(controlLoginStatusBottom, "Please enter your username and password")
                } else {
                    e.updateText(controlLoginStatus, "Please enter your username and password")
                }
                e.updateText(controlLoginUsername, options.rememberUsername != 0 ? options.username : "")
                e.updateText(controlLoginPassword, options.rememberPassword != 0 ? options.password : "")
                e.setFocus(controlLoginUsername)
            } else if p.isClicked(controlWelcomeOptions) {
                showAdditionalOptions = true
            } else if p.isClicked(controlWelcomeWorlds) {
                loginScreen = .world
            }
        case .new:
            let n = panelLoginNewUser!
            n.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                          scrollDelta: mouseScrollDelta)
            if options.accountManagement != 0 {
                if n.isClicked(controlRegisterCancel) { loginScreen = .welcome; return }
                if n.isClicked(controlRegisterUser) { n.setFocus(controlRegisterPassword); return }
                if n.isClicked(controlRegisterPassword) { n.setFocus(controlRegisterConfirmPassword); return }
                if n.isClicked(controlRegisterConfirmPassword) || n.isClicked(controlRegisterSubmit) {
                    let user = n.text(controlRegisterUser)
                    let pass = n.text(controlRegisterPassword)
                    let confirm = n.text(controlRegisterConfirmPassword)
                    if user.isEmpty || pass.isEmpty || confirm.isEmpty {
                        if compact {
                            n.updateText(controlRegisterStatus, "@yel@Please fill in ALL requested")
                            n.updateText(controlRegisterStatusBottom, "@yel@information to continue!")
                        } else {
                            n.updateText(controlRegisterStatus, "@yel@Please fill in ALL requested information to continue!")
                        }
                        return
                    }
                    if pass != confirm {
                        if compact {
                            n.updateText(controlRegisterStatus, "@yel@The two passwords entered")
                            n.updateText(controlRegisterStatusBottom, "@yel@not the same as each other!")
                        } else {
                            n.updateText(controlRegisterStatus, "@yel@The two passwords entered are not the same as each other!")
                        }
                        return
                    }
                    if pass.utf8.count < 5 {
                        n.updateText(controlRegisterStatus, "@yel@Your password must be at least 5 letters long")
                        n.updateText(controlRegisterStatusBottom, "")
                        return
                    }
                    if !n.isActivated(controlRegisterCheckbox) {
                        n.updateText(controlRegisterStatus, "@yel@You must agree to the terms+conditions to continue")
                        return
                    }
                    n.updateText(controlRegisterStatus, "Please wait... creating new account")
                    n.updateText(controlRegisterStatusBottom, "")
                    drawLoginScreens()
                    resetTimings()
                    register(username: user, password: pass)
                }
            } else if n.isClicked(controlLoginNewOk) {
                loginScreen = .welcome
            }
        case .existing:
            let e = panelLoginExistingUser!
            e.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                          scrollDelta: mouseScrollDelta)
            if e.isClicked(controlLoginCancel) {
                loginScreen = .welcome
            } else if e.isClicked(controlLoginUsername) {
                e.setFocus(controlLoginPassword)
            } else if e.isClicked(controlLoginPassword) || e.isClicked(controlLoginOk) {
                loginUsername = e.text(controlLoginUsername)
                loginPass = e.text(controlLoginPassword)
                login(username: loginUsername, password: loginPass, reconnecting: false)
            }
        case .recover: break
        case .world: worldlistHandleMouse()
        }
    }

    // MARK: - ui/worldlist.c

    /// Where worlds.cfg lives; nil uses the built-in list.
    var worldsFileURL: URL? { options.fileURL?.deletingLastPathComponent().appendingPathComponent("worlds.cfg") }

    func worldlistReadPresets() {
        panelLoginWorldlist.clearList(controlListWorlds)
        if let url = worldsFileURL, let data = try? Data(contentsOf: url) {
            worlds = WorldEntry.parse(String(decoding: data, as: UTF8.self))
            return
        }
        worlds = WorldEntry.defaults
        if let url = worldsFileURL {
            let text = worlds.map { "\($0.name) \($0.host) \($0.port) \($0.rsaExponent) \($0.rsaModulus)\n" }.joined()
            try? Data(text.utf8).write(to: url)
        }
    }

    public func worldlistNew() {
        let compact = isCompact
        let x = (compact ? Mudclient.minWidth : Mudclient.vanillaWidth) / 2
        var y = loginBackgroundHeight + 18
        panelLoginWorldlist = makePanel(10)
        let p = panelLoginWorldlist!
        p.addTextCentre(x: x, y: y, text: "Select a world:", font: .bold12, alternativeColour: true)
        y += 12
        let buttonX = (compact ? Mudclient.minWidth : Mudclient.vanillaWidth) - 36
        let buttonY = compact ? Mudclient.minHeight - 24 : Mudclient.vanillaHeight - 32
        p.addButtonBackground(x: buttonX, y: buttonY, width: 60, height: 20)
        p.addTextCentre(x: buttonX, y: buttonY, text: "Back", font: .bold12, alternativeColour: false)
        controlWorldlistButton = p.addButton(x: buttonX, y: buttonY, width: 60, height: 20)
        controlListWorlds = p.addTextListInteractive(x: x - 150, y: y, width: 250, height: 170, font: .regular11,
                                                     maxLength: 256, alternativeColour: true)
        worldlistReadPresets()
        for i in 0..<worlds.count {
            worlds[i].name = worlds[i].name.replacingOccurrences(of: "_", with: " ")
            p.addListEntry(controlListWorlds, index: i, text: worlds[i].name)
        }
        if server.isEmpty {
            let id = options.lastWorld
            worldlistSelect(id >= 0 && id < worlds.count ? id : 0)
        }
    }

    func worldlistSelect(_ index: Int) {
        guard index < worlds.count else { return }
        server = worlds[index].host
        rsaExponent = worlds[index].rsaExponent
        rsaModulus = worlds[index].rsaModulus
        port = worlds[index].port
        options.lastWorld = index
        panelLoginWorldlist.controlActivated[controlListWorlds] = index
    }

    func worldlistHandleMouse() {
        let p = panelLoginWorldlist!
        p.handleMouse(x: mouseX, y: mouseY, lastButton: lastMouseButtonDown, isDown: mouseButtonDown,
                      scrollDelta: mouseScrollDelta)
        if p.isClicked(controlListWorlds) {
            let index = p.controlListEntryMouseOver[controlListWorlds]
            if index >= 0 { worldlistSelect(index) }
        } else if p.isClicked(controlWorldlistButton) {
            loginScreen = .welcome
        }
    }
}
