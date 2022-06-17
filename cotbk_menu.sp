#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

//Some code inspired/from LuffarenMaps plugin
public Plugin myinfo =
{
    name = "COTBK Command Menu",
    author = "tilgep",
    description = "Menu for Castle of the Bladekeeper, (and VIP loading)",
    version = "1.0",
    url = "steamcommunity.com/id/tilgep"
};

enum struct Player
{
    bool sent;
    char steamid[64];
    int uid;
    int index;

    void Reset()
    {
        this.sent = false;
        this.steamid[0] = '\0';
        this.uid = -1;
        this.index = -1;
    }
}

char spellNames[20][32] = {
    "Swords Of Light",
    "Remedy",
    "Crystalkeeper Wings",
    "Cerberus Summon",
    "Flamekeeper Explosion",
    "Damage Limit Break",
    "Resistance Limit Break",
    "Intellect Limit Break",
    "Divine Benediction",
    "Loop Hole",
    "Corrupted Remedy",
    "Crystalkeeper Wings",
    "Cerberus Summon",
    "Flamekeeper Explosion",
    "Intellect Limit Break",
    "Speed Limit Break",
    "Corruption Slug",
    "Corruption Disease",
    "Corruption Sight",
    "Corruption Imprisonment"
};

char lore[9][128] = {
    "A Massive Castle, Located In An Unknown Place.. A Physical Link To The Divine Blade.",
    "A Remnant of A Supreme Elder Being, Controls The Flow of Life, But Not The Death.",
    "In Need Of A Keeper, It Waits... A Keeper Emerges, The Keeper Ascends.",
    "A Mighty Warrior With His 2 Shields, With The Cause of Reviving His Dead Lover.",
    "Deceived By Its Power, The Keeper Was Cast Down... Accepting His Fate.",
    "Centuries Passed, Many Challengers Dead By His Blade... He Became Corrupt.",
    "With The Power of The Blade And His Corrupted Soul... He Casts A Dark Spell.",
    "For His Intent To Outspread Desperation And Death... For He Can Only Die In Battle.",
    "The Blade Awaits Its New Champions... For They Are The Only Hope For Salvation..."
};

Player g_Players[MAXPLAYERS+1];                 //Array of player info
bool g_bLoaded = false;                         //Are we playing bladekeeper?
int g_iCommandManager = INVALID_ENT_REFERENCE;  //Ent reference of manager script
bool g_bLate = false;

public void OnPluginStart()
{
    RegConsoleCmd("sm_commandsmenu", Command_Menu, "Command menu for Castle of the Bladekeeper");
    HookEvent("round_start", Event_RoundStart);
    if(g_bLate)
    {
        OnMapStart();
        FindScriptEnt();
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_bLate = late;
    return APLRes_Success;
}

public void OnPluginEnd()
{
    if(g_bLoaded && g_iCommandManager != INVALID_ENT_REFERENCE)
    {
        SetVariantString("::PluginBasedMenu = false;");
        AcceptEntityInput(g_iCommandManager, "RunScriptCode");
    }
}

public void OnMapStart()
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    if(StrContains(map, "ze_castle_of_the_bladekeeper", false) != -1)
    {
        g_bLoaded = true;
        g_iCommandManager = INVALID_ENT_REFERENCE;
        CreateTimer(5.0, Timer_SendPlayerData, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        g_bLoaded = false;
    }
}

public void OnClientPostAdminCheck(int client)
{
    char id[64];
    GetClientAuthId(client, AuthId_Steam2, id, sizeof(id));
    
    //Store info
    strcopy(g_Players[client].steamid, 64, id);
    g_Players[client].index = client;
    g_Players[client].uid = GetClientUserId(client);
}

public void OnClientDisconnect(int client)
{
    g_Players[client].Reset();
}

public void Event_RoundStart(Event ev, const char[] name, bool dontBroadcast)
{
    if(!g_bLoaded) return;

    //Re-find script ent every round
    CreateTimer(1.0, Timer_FindEnts);
}

public Action Timer_FindEnts(Handle timer)
{
    FindScriptEnt();
    return Plugin_Stop;
}

void FindScriptEnt()
{
    char script[128];
    int entity = INVALID_ENT_REFERENCE;
    
    //Find the script
    while((entity = FindEntityByClassname(entity, "logic_script")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iName", script, sizeof(script));
        if(StrEqual(script, "CommandsMenuManager")) break;
    }
    
    g_iCommandManager = entity;
    
    //Let the script know if we aren't loaded
    if(g_iCommandManager == INVALID_ENT_REFERENCE)
    {
        SetVariantString("::PluginBasedMenu = false;");
        AcceptEntityInput(g_iCommandManager, "RunScriptCode");
    }
    else
    {
        SetVariantString("::PluginBasedMenu = true;");
        AcceptEntityInput(g_iCommandManager, "RunScriptCode");
    }
}

public Action Timer_SendPlayerData(Handle timer)
{
    //Just stop if its not bladekeeper
    if(!g_bLoaded) return Plugin_Stop;

    //Keep going if ent hasn't been found yet
    if(g_iCommandManager == INVALID_ENT_REFERENCE) return Plugin_Continue;

    SendPlayerData();

    return Plugin_Continue;
}

void SendPlayerData()
{
    char buffer[128];
    int sending = 0;

    for(int i = 1; i < sizeof(g_Players); i++)
    {
        if(g_Players[i].sent) continue;
        if(g_Players[i].index <= 0) continue;

        Format(buffer, sizeof(buffer), "%s", g_Players[i].steamid);
        ReplaceString(buffer, sizeof(buffer), ":", "c");
        Format(buffer, sizeof(buffer), "OnUser1 !self:RunScriptCode:ClientValidated(\"%d\" \"%d\" \"%s\");:0.2:1", g_Players[i].index, g_Players[i].uid, buffer);
        SetVariantString(buffer);
        AcceptEntityInput(g_iCommandManager, "AddOutput");
        g_Players[i].sent = true;
        sending++;
    }

    if(sending > 0) AcceptEntityInput(g_iCommandManager, "FireUser1");
}

public Action Command_Menu(int client, int args)
{
    if(!g_bLoaded) return Plugin_Handled;
    if(client == 0 || !IsClientInGame(client)) return Plugin_Handled;
    if(g_iCommandManager == INVALID_ENT_REFERENCE) return Plugin_Handled;

    CreateMainMenu(client);
    return Plugin_Handled;
}

/**
    Creates and displays the main menu to a given client
 */
public void CreateMainMenu(int client)
{
    Menu menu = CreateMenu(MainMenuHandler);
    menu.Pagination = MENU_NO_PAGINATION;
    menu.ExitButton = true;

    //We have data stored in player name to access it here
    char name[PLATFORM_MAX_PATH];
    char infos[32][8];
    GetEntPropString(client, Prop_Data, "m_iName", name, sizeof(name));
    ExplodeString(name, "_", infos, sizeof(infos), sizeof(infos[]));

    menu.SetTitle(" <--COTBK Commands Menu--> ");

    menu.AddItem("upgrade", "Upgrade Stats");
    menu.AddItem("spells", "Spells");
    menu.AddItem("abilities", "Abilities");
    menu.AddItem("lore1", "Story Lore 1");
    menu.AddItem("lore2", "Story Lore 2");
    menu.AddItem("fixspeed", "Fix Speed");
    menu.AddItem("stats", "Stats Info");
    if(infos[31][2]=='1') menu.AddItem("reset", "Reset Points");

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MainMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char item[32];
            GetMenuItem(menu, param2, item, sizeof(item));

            if(StrEqual(item, "upgrade"))
            {
                CreateStatMenu(param1);
            }
            else if(StrEqual(item, "spells"))
            {
                CreateSpellMenu(param1);
            }
            else if(StrEqual(item, "abilities"))
            {
                CreateAbilityMenu(param1);
            }
            else if(StrEqual(item, "lore1"))
            {
                CreateLore1Menu(param1);
            }
            else if(StrEqual(item, "lore2"))
            {
                CreateLore2Menu(param1);
            }
            else if(StrEqual(item, "fixspeed"))
            {
                Format(item, sizeof(item), "PluginFixSpeed();", item);
                SetVariantString(item);
                AcceptEntityInput(g_iCommandManager, "RunScriptCode", param1);

                CreateMainMenu(param1);
            }
            else if(StrEqual(item, "stats"))
            {
                CreateInfoMenu(param1);
            }
            else if(StrEqual(item, "reset"))
            {
                Format(item, sizeof(item), "PluginResetPoints();", item);
                SetVariantString(item);
                AcceptEntityInput(g_iCommandManager, "RunScriptCode", param1);

                CreateTimer(0.1, Timer_CreateMainMenu, GetClientUserId(param1));
            }
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public Action Timer_CreateMainMenu(Handle timer, any data)
{
    int client = GetClientOfUserId(data);
    if(client != 0) CreateMainMenu(client);
    return Plugin_Stop;
}

public void CreateStatMenu(int client)
{
    Menu menu = CreateMenu(StatMenuHandler);
    menu.ExitButton = true;
    menu.ExitBackButton = true;

    //We have data stored in player name to access it here
    char name[MAX_NAME_LENGTH];
    char infos[7][16];
    char bonus[16];
    GetEntPropString(client, Prop_Data, "m_iName", name, sizeof(name));
    ExplodeString(name, "_", infos, sizeof(infos), sizeof(infos[]));
    
    menu.SetTitle(" <--Stats Upgrade Menu--> \nLevel: %s \nPoints Available: %s", infos[0][1], infos[1][1]);

    Format(name, sizeof(name), "Damage (%.1fx)", StringToFloat(infos[2][1]));
    menu.AddItem("Damage", name);

    Format(bonus,sizeof(bonus), "%d", RoundFloat((1.0-StringToFloat(infos[3][1]))*100.0));
    Format(name, sizeof(name), "Resistance (%s%%)", bonus);
    menu.AddItem("Resistance", name);

    Format(name, sizeof(name), "Speed (%sx)", infos[4][1]);
    menu.AddItem("Speed", name);

    Format(name, sizeof(name), "Intellect (%s)", infos[5][1]);
    menu.AddItem("Intellect", name);

    Format(name, sizeof(name), "Luck (%s)", infos[6][1]);
    menu.AddItem("Luck", name);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int StatMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char item[32];
            GetMenuItem(menu, param2, item, sizeof(item));
            
            Format(item, sizeof(item), "PluginLevelUp%s();", item);
            SetVariantString(item);
            AcceptEntityInput(g_iCommandManager, "RunScriptCode", param1);

            //Delay redraw to get accurate info
            CreateTimer(0.1, Timer_ShowStatMenu, GetClientUserId(param1));
        }
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public Action Timer_ShowStatMenu(Handle timer, any data)
{
    int client = GetClientOfUserId(data);
    if(client != 0)
    {
        CreateStatMenu(client);
    }
    return Plugin_Stop;
}

public void CreateSpellMenu(int client)
{
    Menu menu = CreateMenu(SpellMenuHandler);
    menu.SetTitle(" <--Spells Menu--> ");
    menu.ExitBackButton = true;

    //We have data stored in player name to access it here
    char name[MAX_NAME_LENGTH];
    char infos[27][8];
    char temp[4];
    GetEntPropString(client, Prop_Data, "m_iName", name, sizeof(name));
    ExplodeString(name, "_", infos, sizeof(infos), sizeof(infos[]));

    int added = 0;

    if(GetClientTeam(client) == 3)
    {
        for(int i = 7; i < 17; i++)
        {
            int count = StringToInt(infos[i][2]);
            if(count == 0) continue;
            Format(temp, sizeof(temp), "%d", i-7);
            Format(name, sizeof(name), "%s (%d)", spellNames[i-7], count);
            menu.AddItem(temp, name);
            added++;
        }
    }
    else if(GetClientTeam(client) == 2)
    {
        for(int i = 17; i < 27; i++)
        {
            int count = StringToInt(infos[i][2]);
            if(count == 0) continue;
            Format(temp, sizeof(temp), "%d", i-7);
            Format(name, sizeof(name), "%s (%d)", spellNames[i-7], count);
            menu.AddItem(temp, name);
            added++;
        }
    }

    if(added == 0)
    {
        menu.AddItem("none", "None", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int SpellMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char item[64];
            GetMenuItem(menu, param2, item, sizeof(item));
            
            Format(item, sizeof(item), "PluginCast(\"%s\");", spellNames[StringToInt(item)]);
            SetVariantString(item);
            AcceptEntityInput(g_iCommandManager, "RunScriptCode", param1);

            //Delay redraw to get accurate info
            CreateTimer(0.1, Timer_ShowSpellMenu, GetClientUserId(param1));
        }
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public Action Timer_ShowSpellMenu(Handle timer, any data)
{
    int client = GetClientOfUserId(data);
    if(client != 0)
    {
        CreateSpellMenu(client);
    }
    return Plugin_Stop;
}

public void CreateAbilityMenu(int client)
{
    Menu menu = CreateMenu(SpellMenuHandler);
    menu.SetTitle(" <--Abilities Menu--> ");
    menu.ExitBackButton = true;

    //We have data stored in player name to access it here
    char name[MAX_NAME_LENGTH];
    char infos[31][8];
    GetEntPropString(client, Prop_Data, "m_iName", name, sizeof(name));
    ExplodeString(name, "_", infos, sizeof(infos), sizeof(infos[]));
    
    int added = 0;

    if(GetClientTeam(client) == 3)
    {
        if(infos[27][2] == '1')
        {
            menu.AddItem("cb", "Crystal Blessing \n    Ability To Survive The Bladekeeper's Divine Attacks", ITEMDRAW_DISABLED);
            added++;
        }
        if(infos[28][2] == '1')
        {
            menu.AddItem("fb", "Flame Blessing \n    Ability To Inflict Damage Upon The Bladekeeper's Divine Armor", ITEMDRAW_DISABLED);
            added++;
        }
        if(infos[29][2] == '1')
        {
            menu.AddItem("sb", "Soul Of The Bladekeeper \n    .................", ITEMDRAW_DISABLED);
            added++;
        }
    }
    else if(GetClientTeam(client) == 2)
    {
        if(infos[30][2] == '1')
        {
            menu.AddItem("cs", "Corruption Shields \n    Ability To Create Shields That Block Damage", ITEMDRAW_DISABLED);
            added++;
        }
    }

    if(added == 0)
    {
        menu.AddItem("none", "None", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int AbilityMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public void CreateLore1Menu(int client)
{
    Menu menu = CreateMenu(Lore1MenuHandler);
    menu.SetTitle(" <--Lore Entries--> ");
    menu.ExitBackButton = true;

    char name[16];
    int entity = INVALID_ENT_REFERENCE;
    
    //Find the lore data ent
    while((entity = FindEntityByClassname(entity, "game_text")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
        if(StrEqual(name, "LORE_DATA", false))
        {
            GetEntPropString(entity, Prop_Data, "m_iszMessage", name, sizeof(name));
            break;
        }
    }
    
    char buffer[128];
    char temp[4];
    for(int i = 0; i < 5; i++)
    {
        if(name[i] == '1')
        {
            Format(buffer, sizeof(buffer), "%s", lore[i]);
        }
        else
        {
            Format(buffer, sizeof(buffer), "????");
        }
        Format(temp, sizeof(temp), "%d", i);
        menu.AddItem(temp, buffer, ITEMDRAW_DISABLED);
    }
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Lore1MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public void CreateLore2Menu(int client)
{
    Menu menu = CreateMenu(Lore2MenuHandler);
    menu.SetTitle(" <--Lore Entries--> ");
    menu.ExitBackButton = true;

    char name[16];
    int entity = INVALID_ENT_REFERENCE;
    
    //Find the lore data ent
    while((entity = FindEntityByClassname(entity, "game_text")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
        if(StrEqual(name, "LORE_DATA"))
        {
            GetEntPropString(entity, Prop_Data, "m_iszMessage", name, sizeof(name));
            break;
        }
    }

    char buffer[128];
    char temp[4];
    for(int i = 5; i < 9; i++)
    {
        if(name[i] == '1')
        {
            Format(buffer, sizeof(buffer), "%s", lore[i]);
        }
        else
        {
            Format(buffer, sizeof(buffer), "????");
        }
        Format(temp, sizeof(temp), "%d", i);
        menu.AddItem(temp, buffer, ITEMDRAW_DISABLED);
    }
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Lore2MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public void CreateInfoMenu(int client)
{
    Menu menu = CreateMenu(InfoMenuHandler);
    menu.ExitButton = true;
    menu.ExitBackButton = true;

    menu.SetTitle(" <--Stats Info Menu--> ");

    menu.AddItem("Damage", "Damage: Damage Against Bosses & Other Players, Max of: (X2.6)", ITEMDRAW_DISABLED);
    menu.AddItem("Resistance", "Resistance: Amount of Damage You Take From Bosses And Abilities, Max of: (75%)", ITEMDRAW_DISABLED);
    menu.AddItem("Speed", "Speed: General Run & Walk Speed, Max of: (X1.2)", ITEMDRAW_DISABLED);
    menu.AddItem("Intellect", "Intellect: Amount of Damage Dealt By Your Abilities, Max of: (2.5)", ITEMDRAW_DISABLED);
    menu.AddItem("Luck", "Luck: Increase Your Chances Of Getting Drops, Max of: (X2.0)", ITEMDRAW_DISABLED);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int InfoMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}