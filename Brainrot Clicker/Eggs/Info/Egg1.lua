local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetInfos = require(ReplicatedStorage.Modules.Game.Globals.Pets)

local Info = {
    Name = "Egg1",
    Price = 500,
    Type = "Coins",
    
    Items = {
        { Name = "Lirilì Larilà",      Chance = 30,  Info = PetInfos["Lirilì Larilà"]  },
        { Name = "Tim Cheese",         Chance = 30,  Info = PetInfos["Tim Cheese"]   },
        { Name = "Burbaloni Luliloli", Chance = 25,  Info = PetInfos["Burbaloni Luliloli"]   },
        { Name = "Pippy Kiwi",         Chance = 10,  Info = PetInfos["Pippy Kiwi"]    },
        { Name = "Svinina Bombardino", Chance = 4,   Info = PetInfos["Svinina Bombardino"] },
        { Name = "Fruli Frula",        Chance = 1,   Info = PetInfos["Fruli Frula"] },
    }
}

return Info
