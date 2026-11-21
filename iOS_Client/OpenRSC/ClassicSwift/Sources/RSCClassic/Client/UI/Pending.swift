// UI pieces of rsc-c not ported yet. Each is replaced by its port in a
// file named after the rsc-c source (ui/<name>.c); until then they draw nothing.

extension Mudclient {
    func handleSleepInput() {}            // ui/sleep.c
    func drawSleep() {}                   // ui/sleep.c
    func drawStatusBars() {}              // ui/status-bars.c
    func drawUITabs() {}                  // ui/ui-tabs.c
    func setActiveUITab(noMenus: Bool) {} // ui/ui-tabs.c
    func drawActiveUITab(noMenus: Bool) {} // ui/ui-tabs.c
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
    func drawChangePassword() {}          // ui/options-tab.c
    func drawSocialInput() {}             // ui/social-tab.c
    func drawOptionMenu() {}              // ui/option-menu.c
    func drawCombatStyle() {}             // ui/combat-style.c
    func createRightClickMenu() {}        // ui/menu.c
    func drawRightClickMenu() {}          // ui/menu.c
    func createTopMouseMenu() {}          // ui/menu.c
    func drawHoverTooltip() {}            // ui/menu.c
}
