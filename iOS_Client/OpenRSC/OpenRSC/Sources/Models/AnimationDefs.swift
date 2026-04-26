import Foundation

struct AnimationDef {
    let name: String
    let category: String
    let charColour: Int
    let blueMask: Int     // 0 if not specified in constructor
    let genderModel: Int
    let hasA: Bool        // has "attack" fighting animation sprites
    let hasF: Bool        // has "F" special fighting animation
    var number: Int       // base sprite ID, populated by assignAnimationNumbers()
}

enum AnimationDefs {
    static var animations: [AnimationDef] = [
        // index 0 (java //0)
        AnimationDef(name: "head1", category: "player", charColour: 1, blueMask: 0, genderModel: 13, hasA: true, hasF: false, number: 0),
        // index 1 (java //1)
        AnimationDef(name: "body1", category: "player", charColour: 2, blueMask: 0, genderModel: 6, hasA: true, hasF: false, number: 0),
        // index 2 (java //2)
        AnimationDef(name: "legs1", category: "player", charColour: 3, blueMask: 0, genderModel: 15, hasA: true, hasF: false, number: 0),
        // index 3 (java //3)
        AnimationDef(name: "fhead1", category: "player", charColour: 1, blueMask: 0, genderModel: 13, hasA: true, hasF: false, number: 0),
        // index 4 (java //4)
        AnimationDef(name: "fbody1", category: "player", charColour: 2, blueMask: 0, genderModel: 10, hasA: true, hasF: false, number: 0),
        // index 5 (java //5)
        AnimationDef(name: "head2", category: "player", charColour: 1, blueMask: 0, genderModel: 13, hasA: true, hasF: false, number: 0),
        // index 6 (java //6)
        AnimationDef(name: "head3", category: "player", charColour: 1, blueMask: 0, genderModel: 5, hasA: true, hasF: false, number: 0),
        // index 7 (java //7)
        AnimationDef(name: "head4", category: "player", charColour: 1, blueMask: 0, genderModel: 13, hasA: true, hasF: false, number: 0),
        // index 8 (java //8)
        AnimationDef(name: "chefshat", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 9 (java //9)
        AnimationDef(name: "apron", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 10 (java //10)
        AnimationDef(name: "apron", category: "equipment", charColour: 9789488, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 11 (java //11)
        AnimationDef(name: "boots", category: "equipment", charColour: 5592405, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 12 (java //12)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 13 (java //13)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 14 (java //14)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 15 (java //15)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 16 (java //16)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 17 (java //17)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 18 (java //18)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 19 (java //19)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 20 (java //20)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 21 (java //21)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 22 (java //22)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 23 (java //23)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 24 (java //24)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 25 (java //25)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 26 (java //26)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 27 (java //27)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 28 (java //28)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 29 (java //29)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 30 (java //30)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 31 (java //31)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 32 (java //32)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 33 (java //33)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 34 (java //34)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 35 (java //35)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 10083839, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 36 (java //36)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 37 (java //37)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 38 (java //38)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 39 (java //39)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 40 (java //40)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 41 (java //41)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 42 (java //42)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 4210752, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 43 (java //43)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 44 (java //44)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 10083839, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 45 (java //45)
        AnimationDef(name: "leatherarmour", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 46 (java //46)
        AnimationDef(name: "leathergloves", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 47 (java //47)
        AnimationDef(name: "sword", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 48 (java //48)
        AnimationDef(name: "sword", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 49 (java //49)
        AnimationDef(name: "sword", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 50 (java //50)
        AnimationDef(name: "sword", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 51 (java //51)
        AnimationDef(name: "sword", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 52 (java //52)
        AnimationDef(name: "sword", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 53 (java //53)
        AnimationDef(name: "sword", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 54 (java //54)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 55 (java //55)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 56 (java //56)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 57 (java //57)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 58 (java //58)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 59 (java //59)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 60 (java //60)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 61 (java //61)
        AnimationDef(name: "apron", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 62 (java //62)
        AnimationDef(name: "cape", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 63 (java //63)
        AnimationDef(name: "cape", category: "equipment", charColour: 2434341, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 64 (java //64)
        AnimationDef(name: "cape", category: "equipment", charColour: 4210926, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 65 (java //65)
        AnimationDef(name: "cape", category: "equipment", charColour: 4246592, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 66 (java //66)
        AnimationDef(name: "cape", category: "equipment", charColour: 15658560, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 67 (java //67)
        AnimationDef(name: "cape", category: "equipment", charColour: 15636736, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 68 (java //68)
        AnimationDef(name: "cape", category: "equipment", charColour: 11141341, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 69 (java //69)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 70 (java //70)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 71 (java //71)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 72 (java //72)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 73 (java //73)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 74 (java //74)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 75 (java //75)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 76 (java //76)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 255, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 77 (java //77)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 255, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 78 (java //78)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 4210752, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 79 (java //79)
        AnimationDef(name: "necklace", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 80 (java //80)
        AnimationDef(name: "necklace", category: "equipment", charColour: 16763980, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 81 (java //81)
        AnimationDef(name: "skirt", category: "equipment", charColour: 255, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 82 (java //82)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 4210752, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 83 (java //83)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 10510400, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 84 (java //84)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 15609904, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 85 (java //85)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 86 (java //86)
        AnimationDef(name: "skirt", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 87 (java //87)
        AnimationDef(name: "skirt", category: "equipment", charColour: 10510400, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 88 (java //88)
        AnimationDef(name: "skirt", category: "equipment", charColour: 4210752, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 89 (java //89)
        AnimationDef(name: "skirt", category: "equipment", charColour: 16036851, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 90 (java //90)
        AnimationDef(name: "skirt", category: "equipment", charColour: 15609904, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 91 (java //91)
        AnimationDef(name: "skirt", category: "equipment", charColour: 8400921, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 92 (java //92)
        AnimationDef(name: "skirt", category: "equipment", charColour: 7824998, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 93 (java //93)
        AnimationDef(name: "skirt", category: "equipment", charColour: 7829367, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 94 (java //94)
        AnimationDef(name: "skirt", category: "equipment", charColour: 2245205, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 95 (java //95)
        AnimationDef(name: "skirt", category: "equipment", charColour: 4347170, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 96 (java //96)
        AnimationDef(name: "skirt", category: "equipment", charColour: 26214, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 97 (java //97)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 98 (java //98)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 99 (java //99)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 100 (java //100)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 101 (java //101)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 102 (java //102)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 56797, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 103 (java //103)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 104 (java //104)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 16750896, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 105 (java //105)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 11363121, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 106 (java //106)
        AnimationDef(name: "crossbow", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 107 (java //107)
        AnimationDef(name: "longbow", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 108 (java //108)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 109 (java //109)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 110 (java //110)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 111 (java //111)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 112 (java //112)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 113 (java //113)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 114 (java //114)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 115 (java //115)
        AnimationDef(name: "mace", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 116 (java //116)
        AnimationDef(name: "mace", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 117 (java //117)
        AnimationDef(name: "mace", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 118 (java //118)
        AnimationDef(name: "mace", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 119 (java //119)
        AnimationDef(name: "mace", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 120 (java //120)
        AnimationDef(name: "mace", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 121 (java //121)
        AnimationDef(name: "mace", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 122 (java //122)
        AnimationDef(name: "staff", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 123 (java //123)
        AnimationDef(name: "rat", category: "npc", charColour: 4805259, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 124 (java //124)
        AnimationDef(name: "demon", category: "npc", charColour: 16384000, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 125 (java //125)
        AnimationDef(name: "spider", category: "npc", charColour: 13408576, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 126 (java //126)
        AnimationDef(name: "spider", category: "npc", charColour: 16728144, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 127 (java //127)
        AnimationDef(name: "camel", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 128 (java //128)
        AnimationDef(name: "cow", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 129 (java //129)
        AnimationDef(name: "sheep", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 130 (java //130)
        AnimationDef(name: "unicorn", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 131 (java //131)
        AnimationDef(name: "bear", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 132 (java //132)
        AnimationDef(name: "chicken", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 133 (java //133)
        AnimationDef(name: "skeleton", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 134 (java //134)
        AnimationDef(name: "skelweap", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: true, number: 0),
        // index 135 (java //135)
        AnimationDef(name: "zombie", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 136 (java //136)
        AnimationDef(name: "zombweap", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: true, number: 0),
        // index 137 (java //137)
        AnimationDef(name: "ghost", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 138 (java //138)
        AnimationDef(name: "bat", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 139 (java //139)
        AnimationDef(name: "goblin", category: "npc", charColour: 8969727, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 140 (java //140)
        AnimationDef(name: "goblin", category: "npc", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 141 (java //141)
        AnimationDef(name: "goblin", category: "npc", charColour: 47872, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 142 (java //142)
        AnimationDef(name: "gobweap", category: "npc", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: true, number: 0),
        // index 143 (java //143)
        AnimationDef(name: "scorpion", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 144 (java //144)
        AnimationDef(name: "dragon", category: "npc", charColour: 65280, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 145 (java //145)
        AnimationDef(name: "dragon", category: "npc", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 146 (java //146)
        AnimationDef(name: "dragon", category: "npc", charColour: 21981, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 147 (java //147)
        AnimationDef(name: "wolf", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 148 (java //148)
        AnimationDef(name: "wolf", category: "npc", charColour: 10066329, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 149 (java //149)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 150 (java //150)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 16776960, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 151 (java //151)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 255, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 152 (java //152)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 65280, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 153 (java //153)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 16711935, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 154 (java //154)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 155 (java //155)
        AnimationDef(name: "leathergloves", category: "equipment", charColour: 11202303, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 156 (java //156)
        AnimationDef(name: "chicken", category: "npc", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 157 (java //157)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 10083839, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 158 (java //158)
        AnimationDef(name: "skirt", category: "equipment", charColour: 1118481, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 159 (java //159)
        AnimationDef(name: "wolf", category: "npc", charColour: 9789488, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 160 (java //160)
        AnimationDef(name: "spider", category: "npc", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 161 (java //161)
        AnimationDef(name: "battleaxe", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 162 (java //162)
        AnimationDef(name: "sword", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 163 (java //163)
        AnimationDef(name: "eyepatch", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: true, number: 0),
        // index 164 (java //164)
        AnimationDef(name: "demon", category: "npc", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 165 (java //165)
        AnimationDef(name: "dragon", category: "npc", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 166 (java //166)
        AnimationDef(name: "spider", category: "npc", charColour: 14535680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 167 (java //167)
        AnimationDef(name: "wolf", category: "npc", charColour: 2236962, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 168 (java //168)
        AnimationDef(name: "unicorn", category: "npc", charColour: 2236962, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 169 (java //169)
        AnimationDef(name: "demon", category: "npc", charColour: 6291456, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 170 (java //170)
        AnimationDef(name: "spider", category: "npc", charColour: 2236962, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 171 (java //171)
        AnimationDef(name: "necklace", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 172 (java //172)
        AnimationDef(name: "rat", category: "npc", charColour: 11184810, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 173 (java //173)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 11250603, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 174 (java //174)
        AnimationDef(name: "chainmail", category: "equipment", charColour: 11250603, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 175 (java //175)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 176 (java //176)
        AnimationDef(name: "legs1", category: "player", charColour: 9785408, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 177 (java //177)
        AnimationDef(name: "gasmask", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 178 (java //178)
        AnimationDef(name: "mediumhelm", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 179 (java //179)
        AnimationDef(name: "spider", category: "npc", charColour: 3852326, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 180 (java //180)
        AnimationDef(name: "spear", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 181 (java //181)
        AnimationDef(name: "halloweenmask", category: "equipment", charColour: 52224, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 182 (java //182)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 1052688, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 183 (java //183)
        AnimationDef(name: "skirt", category: "equipment", charColour: 1052688, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 184 (java //184)
        AnimationDef(name: "halloweenmask", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 185 (java //185)
        AnimationDef(name: "halloweenmask", category: "equipment", charColour: 255, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 186 (java //186)
        AnimationDef(name: "skirt", category: "equipment", charColour: 16755370, blueMask: 0, genderModel: 15, hasA: true, hasF: false, number: 0),
        // index 187 (java //187)
        AnimationDef(name: "skirt", category: "equipment", charColour: 11206570, blueMask: 0, genderModel: 15, hasA: true, hasF: false, number: 0),
        // index 188 (java //188)
        AnimationDef(name: "skirt", category: "equipment", charColour: 11184895, blueMask: 0, genderModel: 15, hasA: true, hasF: false, number: 0),
        // index 189 (java //189)
        AnimationDef(name: "skirt", category: "equipment", charColour: 16777164, blueMask: 0, genderModel: 15, hasA: true, hasF: false, number: 0),
        // index 190 (java //190)
        AnimationDef(name: "skirt", category: "equipment", charColour: 13434879, blueMask: 0, genderModel: 15, hasA: true, hasF: false, number: 0),
        // index 191 (java //191)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 16755370, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 192 (java //192)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 11206570, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 193 (java //193)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 11184895, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 194 (java //194)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 16777164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 195 (java //195)
        AnimationDef(name: "wizardshat", category: "equipment", charColour: 13434879, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 196 (java //196)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 16755370, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 197 (java //197)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 11206570, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 198 (java //198)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 11184895, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 199 (java //199)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 16777164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 200 (java //200)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 13434879, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 201 (java //201)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 3978097, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 202 (java //202)
        AnimationDef(name: "skirt", category: "equipment", charColour: 3978097, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 203 (java //203)
        AnimationDef(name: "boots", category: "equipment", charColour: 16755370, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 204 (java //204)
        AnimationDef(name: "boots", category: "equipment", charColour: 11206570, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 205 (java //205)
        AnimationDef(name: "boots", category: "equipment", charColour: 11184895, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 206 (java //206)
        AnimationDef(name: "boots", category: "equipment", charColour: 16777164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 207 (java //207)
        AnimationDef(name: "boots", category: "equipment", charColour: 13434879, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 208 (java //208)
        AnimationDef(name: "santahat", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 209 (java //209)
        AnimationDef(name: "ibanstaff", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 210 (java //210)
        AnimationDef(name: "souless", category: "npc", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 211 (java //211)
        AnimationDef(name: "boots", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 212 (java //212)
        AnimationDef(name: "legs1", category: "player", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 213 (java //213)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 8421376, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 214 (java //214)
        AnimationDef(name: "skirt", category: "equipment", charColour: 8421376, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 215 (java //215)
        AnimationDef(name: "cape", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 216 (java //216)
        AnimationDef(name: "wolf", category: "npc", charColour: 13420580, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 217 (java //217)
        AnimationDef(name: "bunnyears", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 218 (java //218)
        AnimationDef(name: "saradominstaff", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 219 (java //219)
        AnimationDef(name: "spear", category: "equipment", charColour: 56797, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 220 (java //220)
        AnimationDef(name: "skirt", category: "equipment", charColour: 1392384, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 221 (java //221)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 1392384, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 222 (java //222)
        AnimationDef(name: "wolf", category: "npc", charColour: 5585408, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 223 (java //223)
        AnimationDef(name: "chicken", category: "npc", charColour: 6893315, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 224 (java //224)
        AnimationDef(name: "squareshield", category: "equipment", charColour: 13500416, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 225 (java //225)
        AnimationDef(name: "cape", category: "equipment", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 226 (java //226)
        AnimationDef(name: "boots", category: "equipment", charColour: 1118481, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 227 (java //227)
        AnimationDef(name: "wizardsrobe", category: "equipment", charColour: 1118481, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 228 (java //228)
        AnimationDef(name: "scythe", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 229 (java //229 - bronze hatchet)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 230 (java //230)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 231 (java //231)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 232 (java //232)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 233 (java //233)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 234 (java //234)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 235 (java //235 black)
        AnimationDef(name: "hatchet", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 236 (java //236 - bronze kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 12274450, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 237 (java //237 - iron kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 11510434, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 238 (java //238 - steel kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 11513775, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 239 (java //239 - black kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 7373718, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 240 (java //240 - mith kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 8623728, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 241 (java //241 - addy kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 48059, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 242 (java //242 - rune kite)
        AnimationDef(name: "kiteshield", category: "equipment", charColour: 2302755, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 243 (java //243 - dragon square)
        AnimationDef(name: "dragonshield", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 244 (java //244 - dragon med)
        AnimationDef(name: "dragonmedhelm", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 245 (java //245 - bronze plate skirt)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 12274450, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 246 (java //246)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 11510434, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 247 (java //247)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 11513775, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 248 (java //248)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 7373718, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 249 (java //249)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 8623728, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 250 (java //250)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 48059, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 251 (java //251)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 2302755, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 252 (java //252 - wooden longbow)
        AnimationDef(name: "longbow", category: "equipment", charColour: 8537122, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 253 (java //253)
        AnimationDef(name: "longbow", category: "equipment", charColour: 11300689, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 254 (java //254)
        AnimationDef(name: "longbow", category: "equipment", charColour: 8941897, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 255 (java //255)
        AnimationDef(name: "longbow", category: "equipment", charColour: 9132849, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 256 (java //256)
        AnimationDef(name: "longbow", category: "equipment", charColour: 10310656, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 257 (java //257)
        AnimationDef(name: "longbow", category: "equipment", charColour: 37281, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 258 (java //258 - bronze short sword)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 259 (java //259)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 260 (java //260)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 261 (java //261)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 262 (java //262)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 263 (java //263)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 264 (java //264)
        AnimationDef(name: "shortsword", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 265 (java //265 - bronze dagger)
        AnimationDef(name: "dagger", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 266 (java //266)
        AnimationDef(name: "dagger", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 267 (java //267)
        AnimationDef(name: "dagger", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 268 (java //268)
        AnimationDef(name: "dagger", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 269 (java //269)
        AnimationDef(name: "dagger", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 270 (java //270)
        AnimationDef(name: "dagger", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 271 (java //271)
        AnimationDef(name: "dagger", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 272 (java //272 - bronze p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 273 (java //273 - iron p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 274 (java //274 - steel p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 275 (java //275 - mith p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 276 (java //276 - addy p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 277 (java //277 - rune p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 278 (java //278 - black p dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 279 (java //279 - bronze 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 280 (java //280 - iron 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 281 (java //281 - steel 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 282 (java //282 - black 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 283 (java //283 - mith 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 284 (java //284 - addy 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 285 (java //285 - rune 2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 286 (java //286 - white unicorn mask)
        AnimationDef(name: "unicornmask", category: "equipment", charColour: 16777215, blueMask: 16777215, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 287 (java //287 - blood unicorn mask)
        AnimationDef(name: "unicornmask", category: "equipment", charColour: 10878976, blueMask: 1513239, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 288 (java //288 - black unicorn mask)
        AnimationDef(name: "unicornmask", category: "equipment", charColour: 1513239, blueMask: 10878976, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 289 (java //289 - pink unicorn mask)
        AnimationDef(name: "unicornmask", category: "equipment", charColour: 16759039, blueMask: 16777215, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 290 (java //290 - white wolf mask)
        AnimationDef(name: "wolfmask", category: "equipment", charColour: 16777215, blueMask: 16777215, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 291 (java //291 - blood wolf mask)
        AnimationDef(name: "wolfmask", category: "equipment", charColour: 10878976, blueMask: 1513239, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 292 (java //292 - black wolf mask)
        AnimationDef(name: "wolfmask", category: "equipment", charColour: 1513239, blueMask: 10878976, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 293 (java //293 - pink wolf mask)
        AnimationDef(name: "wolfmask", category: "equipment", charColour: 16759039, blueMask: 16777215, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 294 (java //294 - dragon large)
        AnimationDef(name: "dragonfullhelm", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 295 (java //295 - dragon plate)
        AnimationDef(name: "dragonbody", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 296 (java //296 - dragon legs)
        AnimationDef(name: "dragonlegs", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 297 (java //297 - (does not alter))
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 298 (java //298 - female dragon top)
        AnimationDef(name: "fdragontop", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 299 (java //299 - dragon skirt)
        AnimationDef(name: "dragonskirt", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 300 (java //300 - (does not alter))
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 301 (java //301 - (does not alter))
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 302 (java //302 - (does not alter))
        AnimationDef(name: "hatchet", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 303 (java //303 - orange pumpkin head (missing, was using charColour 0))
        AnimationDef(name: "wolf", category: "npc", charColour: 2039583, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 304 (java //304 - red pumpkin head (missing, was 1513239))
        AnimationDef(name: "wolf", category: "npc", charColour: 2039583, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 305 (java //305 - yellow pumpkin head (missing, was 16776960))
        AnimationDef(name: "wolf", category: "npc", charColour: 2039583, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 306 (java //306 - blue pumpkin head (missing))
        AnimationDef(name: "wolf", category: "npc", charColour: 255, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 307 (java //307 - purple pumpkin head (missing))
        AnimationDef(name: "wolf", category: "npc", charColour: 11141375, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 308 (java //308 - green pumpkin head (missing))
        AnimationDef(name: "wolf", category: "npc", charColour: 65280, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 309 (java //309 - fishing cape)
        AnimationDef(name: "fishingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 310 (java //310 - cooking cape)
        AnimationDef(name: "cookingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 311 (java //311 - fishing hood)
        AnimationDef(name: "hood1", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 312 (java //312 - warrior cape)
        AnimationDef(name: "warriorcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 313 (java //313 - spotted cape)
        AnimationDef(name: "spottedcape", category: "equipment", charColour: 7692086, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 314 (java //314 - attack cape)
        AnimationDef(name: "attackcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 315 (java //315 - NPC Gaia (missing))
        AnimationDef(name: "evilhoodie", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 316 (java //316 - easter basket (missing))
        AnimationDef(name: "peppermintstick", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 317 (java //317 - ironman helm)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 318 (java //318 - ironman plate)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 319 (java //319 - ironman legs)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 320 (java //320 - ultimate ironman helm)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 321 (java //321 - ultimate ironman plate)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 322 (java //322 - ultimate ironman legs)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 323 (java //323 - hc ironman helm)
        AnimationDef(name: "fullhelm", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 324 (java //324 - hc ironman plate)
        AnimationDef(name: "platemailtop", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 325 (java //325 - hc ironman legs)
        AnimationDef(name: "platemaillegs", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 326 (java //326 - bronze helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 327 (java //327 - iron helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 328 (java //328 - steel helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 329 (java //329 - black helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 330 (java //330 - mith helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 331 (java //331 - addy helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 332 (java //332 - rune helm orange)
        AnimationDef(name: "fullhelmorange", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 333 (java //333 - bronze helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 334 (java //334 - iron helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 335 (java //335 - steel helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 336 (java //336 - black helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 337 (java //337 - mith helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 338 (java //338 - addy helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 339 (java //339 - rune helm blue)
        AnimationDef(name: "fullhelmblue", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 340 (java //340 - bronze helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 341 (java //341 - iron helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 342 (java //342 - steel helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 343 (java //343 - black helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 344 (java //344 - mith helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 345 (java //345 - addy helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 346 (java //346 - rune helm purple)
        AnimationDef(name: "fullhelmpurple", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 347 (java //347 - bronze helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 348 (java //348 - iron helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 349 (java //349 - steel helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 350 (java //350 - black helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 351 (java //351 - mith helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 352 (java //352 - addy helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 353 (java //353 - rune helm yellow)
        AnimationDef(name: "fullhelmyellow", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 354 (java //354 - bronze helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 355 (java //355 - iron helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 356 (java //356 - steel helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 357 (java //357 - black helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 358 (java //358 - mith helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 359 (java //359 - addy helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 360 (java //360 - rune helm green)
        AnimationDef(name: "fullhelmgreen", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 361 (java //361 - bronze helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 362 (java //362 - iron helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 363 (java //363 - steel helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 364 (java //364 - black helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 365 (java //365 - mith helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 366 (java //366 - addy helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 367 (java //367 - rune helm grey)
        AnimationDef(name: "fullhelmgrey", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 368 (java //368 - bronze helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 369 (java //369 - iron helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 370 (java //370 - steel helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 371 (java //371 - black helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 372 (java //372 - mith helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 373 (java //373 - addy helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 374 (java //374 - rune helm black)
        AnimationDef(name: "fullhelmblack", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 375 (java //375 - bronze helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 376 (java //376 - iron helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 377 (java //377 - steel helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 378 (java //378 - black helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 379 (java //379 - mith helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 380 (java //380 - addy helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 381 (java //381 - rune helm white)
        AnimationDef(name: "fullhelmwhite", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 382 (java //382 NPC Greatwood tree boss (missing))
        AnimationDef(name: "evilhoodie", category: "equipment", charColour: 5453066, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 383 (java //383 smithing cape)
        AnimationDef(name: "smithingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 384 (java //384 strength cape)
        AnimationDef(name: "strengthcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 385 (java //385 hits cape)
        AnimationDef(name: "hitscape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 386 (java //386 - fox mask)
        AnimationDef(name: "wolfmask", category: "equipment", charColour: 16730368, blueMask: 16446686, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 387 (java //387 - bronze spear)
        AnimationDef(name: "spear", category: "equipment", charColour: 12274450, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 388 (java //388 - iron spear)
        AnimationDef(name: "spear", category: "equipment", charColour: 11510434, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 389 (java //389 - steel spear)
        AnimationDef(name: "spear", category: "equipment", charColour: 11513775, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 390 (java //390 - mith spear)
        AnimationDef(name: "spear", category: "equipment", charColour: 7373718, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 391 (java //391 - addy spear)
        AnimationDef(name: "spear", category: "equipment", charColour: 8623728, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 392 (java //392 - rune spear)
        AnimationDef(name: "spear", category: "equipment", charColour: 48059, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 393 (java //393)
        AnimationDef(name: "xmasapron", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 394 (java //394)
        AnimationDef(name: "xmascape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 395 (java //395)
        AnimationDef(name: "santabody", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 396 (java //396)
        AnimationDef(name: "santalegs", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 397 (java //397)
        AnimationDef(name: "santahat2", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 398 (java //398)
        AnimationDef(name: "santamittens", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 399 (java //399)
        AnimationDef(name: "satansgloveswht", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 400 (java //400)
        AnimationDef(name: "greensantahat", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 401 (java //401)
        AnimationDef(name: "antlers", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 402 (java //402 d2h)
        AnimationDef(name: "2hander", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 403 (java //403)
        AnimationDef(name: "dragonscalemail", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 404 (java //404)
        AnimationDef(name: "necklace2", category: "equipment", charColour: 16763980, blueMask: 19711, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 405 (java //405)
        AnimationDef(name: "amulet", category: "equipment", charColour: 16763980, blueMask: 19711, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 406 (java //406)
        AnimationDef(name: "necklace2", category: "equipment", charColour: 16763980, blueMask: 3394611, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 407 (java //407)
        AnimationDef(name: "amulet", category: "equipment", charColour: 16763980, blueMask: 3394611, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 408 (java //408)
        AnimationDef(name: "necklace2", category: "equipment", charColour: 16763980, blueMask: 16724736, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 409 (java //409)
        AnimationDef(name: "amulet", category: "equipment", charColour: 16763980, blueMask: 16724736, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 410 (java //410)
        AnimationDef(name: "necklace2", category: "equipment", charColour: 16763980, blueMask: 16184564, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 411 (java //411)
        AnimationDef(name: "amulet", category: "equipment", charColour: 16763980, blueMask: 16184564, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 412 (java //412)
        AnimationDef(name: "necklace2", category: "equipment", charColour: 16763980, blueMask: 12255487, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 413 (java //413)
        AnimationDef(name: "amulet", category: "equipment", charColour: 16763980, blueMask: 12255487, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 414 (java //414)
        AnimationDef(name: "amulet2", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 415 (java //415)
        AnimationDef(name: "amulet2", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 416 (java //416)
        AnimationDef(name: "lucians", category: "equipment", charColour: 3158064, blueMask: 12750123, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 417 (java //417)
        AnimationDef(name: "lucians", category: "equipment", charColour: 0, blueMask: 12750123, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 418 (java //418)
        AnimationDef(name: "necklace2", category: "equipment", charColour: 0, blueMask: 3394611, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 419 (java //419)
        AnimationDef(name: "sarasymbol", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 420 (java //420)
        AnimationDef(name: "zammysymbol", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 421 (java //421)
        AnimationDef(name: "elementalstaff", category: "equipment", charColour: 714212, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 422 (java //422)
        AnimationDef(name: "elementalstaff", category: "equipment", charColour: 262620, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 423 (java //423)
        AnimationDef(name: "elementalstaff", category: "equipment", charColour: 6565377, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 424 (java //424)
        AnimationDef(name: "elementalstaff", category: "equipment", charColour: 13894147, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 425 (java //425)
        AnimationDef(name: "leatherchaps", category: "equipment", charColour: 3, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 426 (java //426)
        AnimationDef(name: "fleatherbody", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 427 (java //427)
        AnimationDef(name: "leatherskirt", category: "equipment", charColour: 3, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 428 (java //428)
        AnimationDef(name: "thievingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 429 (java //429)
        AnimationDef(name: "fletchingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 430 (java //430)
        AnimationDef(name: "miningcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 431 (java //431)
        AnimationDef(name: "plaguemask", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 432 (java //432)
        AnimationDef(name: "rubberchicken", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 433
        AnimationDef(name: "pickaxe", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 434
        AnimationDef(name: "pickaxe", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 435
        AnimationDef(name: "pickaxe", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 436
        AnimationDef(name: "pickaxe", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 437
        AnimationDef(name: "pickaxe", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 438
        AnimationDef(name: "pickaxe", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 439 (java //439)
        AnimationDef(name: "magiccape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 440 (java //440)
        AnimationDef(name: "craftingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 441
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 442
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 443
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 444
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 445
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 446
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 447
        AnimationDef(name: "chainmaillegs", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 448 (java //448 - dragon kite shield)
        AnimationDef(name: "dragonkiteshield", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 449 (java //449 - white ctf flag)
        AnimationDef(name: "ctfflag", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 450 (java //450 - guthix ctf flag)
        AnimationDef(name: "ctfflag", category: "equipment", charColour: 4246592, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 451 (java //451 - saradomin ctf flag)
        AnimationDef(name: "ctfflag", category: "equipment", charColour: 4210926, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 452 (java //452 - zamorak ctf flag)
        AnimationDef(name: "ctfflag", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 453 (java //453 - white wings)
        AnimationDef(name: "wings", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 454 (java //454 - medium valkyrie helmet)
        AnimationDef(name: "mvalkyriehelm", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 455 (java //455 - medium guthix valkyrie helmet)
        AnimationDef(name: "mvalkyriehelm", category: "equipment", charColour: 4246592, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 456 (java //456 - medium saradomin valkyrie helmet)
        AnimationDef(name: "mvalkyriehelm", category: "equipment", charColour: 4210926, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 457 (java //457 - medium zamorak valkyrie helmet)
        AnimationDef(name: "mvalkyriehelm", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 458 (java //458 - large valkyrie helmet)
        AnimationDef(name: "valkyriehelm", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 459 (java //459 - large guthix valkyrie helmet)
        AnimationDef(name: "valkyriehelm", category: "equipment", charColour: 4246592, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 460 (java //460 - large saradomin valkyrie helmet)
        AnimationDef(name: "valkyriehelm", category: "equipment", charColour: 4210926, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 461 (java //461 - large zamorak valkyrie helmet)
        AnimationDef(name: "valkyriehelm", category: "equipment", charColour: 16711680, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 462 (java //462 - guthix cape)
        AnimationDef(name: "guthixcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 463 (java //463 - saradomin cape)
        AnimationDef(name: "saracape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 464 (java //464 - zamorak cape)
        AnimationDef(name: "zammycape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 465 (java //465 - guthix wings)
        AnimationDef(name: "wings", category: "equipment", charColour: 4246592, blueMask: 1513239, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 466 (java //466 - saradomin wings)
        AnimationDef(name: "wings", category: "equipment", charColour: 4210926, blueMask: 1513239, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 467 (java //467 - zamorak wings)
        AnimationDef(name: "wings", category: "equipment", charColour: 16711680, blueMask: 1513239, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 468 (java //468 - dragon dagger)
        AnimationDef(name: "dagger", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 469 (java //469 - poison dragon dagger)
        AnimationDef(name: "poisoneddagger", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 470 (java //470 - dragon crossbow)
        AnimationDef(name: "crossbow", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 471 (java //471 - dragon longbow)
        AnimationDef(name: "longbow", category: "equipment", charColour: 16711748, blueMask: 0, genderModel: 0, hasA: false, hasF: false, number: 0),
        // index 472 (java //472)
        AnimationDef(name: "bunny", category: "npc", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 473 (java //473)
        AnimationDef(name: "duck", category: "npc", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 474 (java //474)
        AnimationDef(name: "bunnymorph", category: "npc", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 475 (java //475)
        AnimationDef(name: "eggmorph", category: "npc", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 476 (java //476 Bronze Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 477 (java //477 Iron Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 478 (java //478 Steel Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 479 (java //479 Black Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 480 (java //480 Mithril Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 481 (java //481 Adamantite Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 482 (java //482 Rune Scimitar)
        AnimationDef(name: "scimitar", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 483 (java //483 death mask)
        AnimationDef(name: "deathmask", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 484 (java //484 yoyo in hand)
        AnimationDef(name: "yoyo", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 485 (java //485 yoyo up-down 1)
        AnimationDef(name: "yoyo_anim_1", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 486 (java //486 yoyo up-down 2)
        AnimationDef(name: "yoyo_anim_2", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 487 (java //487 yoyo up-down 3)
        AnimationDef(name: "yoyo_anim_3", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 488 (java //488 yoyo up-down 4)
        AnimationDef(name: "yoyo_anim_4", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 489 (java //489 yoyo crazy 1'oclock)
        AnimationDef(name: "yoyo_anim_crazy_1", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 490 (java //490 yoyo crazy 2'oclock)
        AnimationDef(name: "yoyo_anim_crazy_2", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 491 (java //491 yoyo crazy 3'oclock)
        AnimationDef(name: "yoyo_anim_crazy_3", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 492 (java //492 yoyo crazy 4'oclock)
        AnimationDef(name: "yoyo_anim_crazy_4", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 493 (java //493 yoyo crazy 5'oclock)
        AnimationDef(name: "yoyo_anim_crazy_5", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 494 (java //494 yoyo crazy 7'oclock)
        AnimationDef(name: "yoyo_anim_crazy_7", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 495 (java //495 yoyo crazy 8'oclock)
        AnimationDef(name: "yoyo_anim_crazy_8", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 496 (java //496 yoyo crazy 9'oclock)
        AnimationDef(name: "yoyo_anim_crazy_9", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 497 (java //497 yoyo crazy 10'oclock)
        AnimationDef(name: "yoyo_anim_crazy_10", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 498 (java //498 yoyo crazy 11'oclock)
        AnimationDef(name: "yoyo_anim_crazy_11", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 499 (java //499 yoyo crazy 12'oclock)
        AnimationDef(name: "yoyo_anim_crazy_12", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 500 (java //500 ogre ears)
        AnimationDef(name: "ogreears", category: "equipment", charColour: 11927325, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 501 (java //501 leather vest)
        AnimationDef(name: "leathervest", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 502 (java //502)
        AnimationDef(name: "crown", category: "equipment", charColour: 16763980, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 503 (java //503)
        AnimationDef(name: "crown", category: "equipment", charColour: 19711, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 504 (java //504)
        AnimationDef(name: "crown", category: "equipment", charColour: 3394611, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 505 (java //505)
        AnimationDef(name: "crown", category: "equipment", charColour: 16724736, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 506 (java //506)
        AnimationDef(name: "crown", category: "equipment", charColour: 16184564, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 507 (java //507)
        AnimationDef(name: "crown", category: "equipment", charColour: 12255487, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 508 (java //508)
        AnimationDef(name: "halloweenmask", category: "equipment", charColour: 16711935, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 509 (java //509)
        AnimationDef(name: "pridecape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 510 (java //510)
        AnimationDef(name: "halloweenmask", category: "equipment", charColour: 4, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 511 (java //511)
        AnimationDef(name: "agilitycape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 512 (java //512)
        AnimationDef(name: "defensecape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 513 (java //513)
        AnimationDef(name: "firemakingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 514 (java //514)
        AnimationDef(name: "herblawcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 515 (java //515)
        AnimationDef(name: "hitscape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 516 (java //516)
        AnimationDef(name: "prayercape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 517 (java //517)
        AnimationDef(name: "rangingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 518 (java //518)
        AnimationDef(name: "woodcuttingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 519 (java //519)
        AnimationDef(name: "harvestingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 520 (java //520)
        AnimationDef(name: "runecraftingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 521 (java //521)
        AnimationDef(name: "questcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 522 (java //522)
        AnimationDef(name: "fishingcape", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 523 (java //523 bronze)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 16737817, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 524 (java //524 iron)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 15654365, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 525 (java //525 steel)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 15658734, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 526 (java //526 mithril)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 10072780, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 527 (java //527 adamant)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 11717785, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 528 (java //528 rune)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 65535, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 529 (java //529 black)
        AnimationDef(name: "fchainmail", category: "equipment", charColour: 3158064, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 530 (java //530)
        AnimationDef(name: "fdragonscalemail", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 531 (java //531)
        AnimationDef(name: "mortimertorso", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 532 (java //532)
        AnimationDef(name: "randolphtorso", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 533 (java //533)
        AnimationDef(name: "biggum", category: "npc", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 534 (java //534 - ironman plate top)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 535 (java //535 - ultimate ironman plate top)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 536 (java //536 - hc ironman plate top)
        AnimationDef(name: "fplatemailtop", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 537 (java //537 - ironman plated skirt)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 11189164, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 538 (java //538 - ultimate ironman palted skirt)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 16768685, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 539 (java //539 - hc ironman plated skirt)
        AnimationDef(name: "armorskirt", category: "equipment", charColour: 10027084, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 540 (java //540 - pink halloween mask)
        AnimationDef(name: "halloweenmask_pink", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 541 (java //541)
        AnimationDef(name: "skeletonmorph", category: "npc", charColour: 16777215, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 542 (java //542 - red)
        AnimationDef(name: "christmassweater", category: "equipment", charColour: 8519937, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 543 (java //543 - yellow)
        AnimationDef(name: "christmassweater", category: "equipment", charColour: 12830990, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 544 (java //544 - blue)
        AnimationDef(name: "christmassweater", category: "equipment", charColour: 76930, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 545 (java //545 - purple)
        AnimationDef(name: "christmassweater", category: "equipment", charColour: 6816949, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 546 (java //546 - orange)
        AnimationDef(name: "christmassweater", category: "equipment", charColour: 13596162, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 547 (java //547 - green)
        AnimationDef(name: "christmassweater", category: "equipment", charColour: 1073413, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 548 (java //548 - black party hat)
        AnimationDef(name: "partyhat", category: "equipment", charColour: 1710618, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 549 (java //549 - pink santa hat)
        AnimationDef(name: "pinksantahat", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 550 (java //550 - red)
        AnimationDef(name: "fchristmassweater", category: "equipment", charColour: 8519937, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 551 (java //551 - yellow)
        AnimationDef(name: "fchristmassweater", category: "equipment", charColour: 12830990, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 552 (java //552 - blue)
        AnimationDef(name: "fchristmassweater", category: "equipment", charColour: 76930, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 553 (java //553 - purple)
        AnimationDef(name: "fchristmassweater", category: "equipment", charColour: 6816949, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 554 (java //554 - orange)
        AnimationDef(name: "fchristmassweater", category: "equipment", charColour: 13596162, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 555 (java //555 - green)
        AnimationDef(name: "fchristmassweater", category: "equipment", charColour: 1073413, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 556 (java //556)
        AnimationDef(name: "boomstick", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 557 (java //557)
        AnimationDef(name: "ashtorso", category: "equipment", charColour: 0, blueMask: 0, genderModel: 0, hasA: true, hasF: false, number: 0),
        // index 558 (java //558)
        AnimationDef(name: "amulet", category: "equipment", charColour: 16763980, blueMask: 3, genderModel: 0, hasA: true, hasF: false, number: 0),
    ]

    static func get(_ id: Int) -> AnimationDef? {
        guard id >= 0 && id < animations.count else { return nil }
        return animations[id]
    }

    static var count: Int { animations.count }
}
