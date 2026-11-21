// Port of rsc-c ui/offer-x.c: the "Enter an amount" dialog and the
// Deposit-1/5/10/50/X/All menu entries.

import Foundation

extension Mudclient {
    static let offerXWidth = 164, offerXHeight = 70, offerXCancelSize = 40

    func drawOfferX() {
        let dialogX = surface.width / 2 - Mudclient.offerXWidth / 2
        let dialogY = surface.height / 2 - Mudclient.offerXHeight / 2
        let cancelX = surface.width / 2 - Mudclient.offerXCancelSize / 2
        let cancelY = surface.height / 2 + Mudclient.offerXCancelSize / 2
        surface.drawBox(x: dialogX, y: dialogY, width: Mudclient.offerXWidth, height: Mudclient.offerXHeight,
                        colour: Colour.black)
        surface.drawBorder(x: dialogX, y: dialogY, width: Mudclient.offerXWidth, height: Mudclient.offerXHeight,
                           colour: Colour.white)
        let x = surface.width / 2
        var y = dialogY + 20
        surface.drawStringCentre("Enter an amount", x: x, y: y, font: .bold14, colour: Colour.white)
        if isTouch && mouseButtonClick != 0 && mouseX > dialogX && mouseX < dialogX + Mudclient.offerXWidth &&
            mouseY >= y && mouseY <= y + 30 {
            triggerKeyboard(text: inputDigitsCurrent, isPassword: false, x: dialogX, y: y + 1,
                            width: Mudclient.offerXWidth - 3, height: 30, font: .bold14, isCentred: true)
        }
        y += 20
        surface.drawStringCentre("\(inputDigitsCurrent)*", x: x, y: y, font: .bold14, colour: Colour.white)
        var colour = Colour.white
        if mouseX > cancelX && mouseX < cancelX + Mudclient.offerXCancelSize &&
            mouseY > cancelY && mouseY < cancelY + Mudclient.offerXCancelSize {
            colour = Colour.yellow
        }
        surface.drawStringCentre("Cancel", x: x, y: y + 23, font: .bold12, colour: colour)
    }

    func handleOfferXInput() {
        let cancelX = surface.width / 2 - Mudclient.offerXCancelSize / 2
        let cancelY = surface.height / 2 + Mudclient.offerXCancelSize / 2
        if mouseButtonClick == 1 && mouseX > cancelX && mouseX < cancelX + Mudclient.offerXCancelSize &&
            mouseY > cancelY && mouseY < cancelY + Mudclient.offerXCancelSize {
            inputDigitsCurrent = ""
            showDialogOfferX = false
            mouseButtonClick = 0
        }
    }

    func addOfferMenu(type: Int, itemId: Int, amount: Int, display: String, itemName: String) {
        withMenuEntry { e in
            e.actionText = display
            e.targetText = itemName
            e.type = type
            e.index = itemId
            e.targetIndex = amount
        }
        menuItemsCount += 1
    }

    func addOfferMenus(_ typeString: String, type: Int, itemId: Int, itemAmount: Int, itemName: String, lastX: Int) {
        for n in [1, 5, 10, 50] where itemAmount >= n {
            addOfferMenu(type: type, itemId: itemId, amount: n, display: "\(typeString)-\(n)", itemName: itemName)
        }
        if options.offerX != 0 && options.lastOfferX != 0 {
            if lastX != 0 && lastX != 1 && lastX != 5 && lastX != 10 && lastX != 50 && itemAmount >= lastX {
                addOfferMenu(type: type, itemId: itemId, amount: lastX, display: "\(typeString)-\(lastX)",
                             itemName: itemName)
            }
        }
        if options.offerX != 0 && itemAmount > 1 {
            addOfferMenu(type: type, itemId: itemId, amount: -itemAmount, display: "\(typeString)-X", itemName: itemName)
        }
        if options.offerX != 0 && itemAmount >= 1 {
            addOfferMenu(type: type, itemId: itemId, amount: itemAmount, display: "\(typeString)-All",
                         itemName: itemName)
        }
        withMenuEntry { e in
            e.actionText = "Examine"
            e.targetText = itemName
            e.type = MenuType.inventoryExamine
            e.index = itemId
        }
        menuItemsCount += 1
    }
}
