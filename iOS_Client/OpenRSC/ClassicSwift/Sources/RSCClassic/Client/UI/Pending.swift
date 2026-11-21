// UI pieces of rsc-c not ported yet. Each is replaced by its port in a
// file named after the rsc-c source (ui/<name>.c); until then they draw nothing.

extension Mudclient {
    func handleSleepInput() {}            // ui/sleep.c
    func drawSleep() {}                   // ui/sleep.c
    func drawStatusBars() {}              // ui/status-bars.c
    func drawExperienceDrops() {}         // ui/experience-drops.c
    func drawWelcome() {}                 // ui/welcome.c
    func drawServerMessage() {}           // ui/server-message.c
    func drawWildernessWarning() {}       // ui/wilderness-warning.c
    func drawBank() {}                    // ui/bank.c
    func drawShop() {}                    // ui/shop.c
    func drawTradeConfirm() {}            // ui/trade.c
    func drawTrade() {}                   // ui/trade.c
    func drawDuelConfirm() {}             // ui/duel.c
    func drawDuel() {}                    // ui/duel.c
    func drawOptionMenu() {}              // ui/option-menu.c
    func drawCombatStyle() {}             // ui/combat-style.c
    func bankTransaction(itemId: Int, amount: Int, opcode: Int) {}          // ui/bank.c
    func offerTransactionItem(opcode: Int, itemId: Int, amount: Int) {}     // ui/transaction.c
    func removeTransactionItem(opcode: Int, itemId: Int, amount: Int) {}    // ui/transaction.c
}
