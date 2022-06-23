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
    version = "1.1",
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

Player g_Players[MAXPLAYERS+1];                 //Array of player info
bool g_bLoaded = false;                         //Are we playing bladekeeper?
int g_iCommandManager = INVALID_ENT_REFERENCE;  //Ent reference of manager script
bool g_bLate = false;

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("cotbk_menu.phrases");
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
    CreateTimer(1.5, Timer_FindEnts);
}

public Action Timer_FindEnts(Handle timer)
{
    FindScriptEnt();
    return Plugin_Stop;
}

void FindScriptEnt()
{
    char script[128];

    // Avoid searching if ent stays the same
    if(g_iCommandManager != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(g_iCommandManager, Prop_Data, "m_iName", script, sizeof(script));
        if(StrEqual(script, "CommandsMenuManager")) return;
    }

    int entity = INVALID_ENT_REFERENCE;
    
    //Find the script
    while((entity = FindEntityByClassname(entity, "logic_script")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iName", script, sizeof(script));
        if(StrEqual(script, "CommandsMenuManager")) break;
    }
    
    g_iCommandManager = entity;
    
    //Let the script know if we aren't loaded
    if(g_iCommandManager != INVALID_ENT_REFERENCE)
    {
        SetVariantString("::PluginBasedMenu = true;");
        AcceptEntityInput(g_iCommandManager, "RunScriptCode");
    }
    else
    {
        entity = CreateEntityByName("info_target");
        if(entity!=-1)
        {
            SetVariantString("::PluginBasedMenu = false;");
            AcceptEntityInput(entity, "RunScriptCode");
            CreateTimer(0.1, Timer_KillEnt, entity);
        }
    }
}

public Action Timer_KillEnt(Handle timer, any ent)
{
    if(IsValidEntity(ent))
    {
        AcceptEntityInput(ent, "Kill");
    }
    return Plugin_Stop;
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

    menu.SetTitle("%T", "Main Menu Title", client);

    Format(name, sizeof(name), "%T", "Upgrade", client);
    menu.AddItem("upgrade", name);

    Format(name, sizeof(name), "%T", "Spells", client);
    menu.AddItem("spells", name);

    Format(name, sizeof(name), "%T", "Abilities", client);
    menu.AddItem("abilities", name);

    Format(name, sizeof(name), "%T", "Lore 1", client);
    menu.AddItem("lore1", name);

    Format(name, sizeof(name), "%T", "Lore 2", client);
    menu.AddItem("lore2", name);

    Format(name, sizeof(name), "%T", "Fix Speed", client);
    menu.AddItem("fixspeed", name);

    Format(name, sizeof(name), "%T", "Stats", client);
    menu.AddItem("stats", name);

    if(infos[31][2] == '1') 
    {
        Format(name, sizeof(name), "%T", "Reset Points", client);
        menu.AddItem("reset", name);
    }

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
                Format(item, sizeof(item), "PluginFixSpeed();");
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
                CreateResetMenu(param1);
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
    char name[PLATFORM_MAX_PATH];
    char infos[7][16];
    char bonus[16];
    GetEntPropString(client, Prop_Data, "m_iName", name, sizeof(name));
    ExplodeString(name, "_", infos, sizeof(infos), sizeof(infos[]));
    
    menu.SetTitle("%T\n%T\n%T", "Stats Menu Title", client, "Stats Level", client, infos[0][1], "Stats Points Available", client, infos[1][1]);

    Format(name, sizeof(name), "%T", "Stats Menu Damage", client, infos[2][1]);
    menu.AddItem("Damage", name);

    Format(bonus,sizeof(bonus), "%d", RoundFloat((1.0-StringToFloat(infos[3][1]))*100.0));
    Format(name, sizeof(name), "%T", "Stats Menu Resistance", client, bonus);
    menu.AddItem("Resistance", name);

    Format(name, sizeof(name), "%T", "Stats Menu Speed", client, infos[4][1]);
    menu.AddItem("Speed", name);

    Format(name, sizeof(name), "%T", "Stats Menu Intellect", client, infos[5][1]);
    menu.AddItem("Intellect", name);

    Format(name, sizeof(name), "%T", "Stats Menu Luck", client, infos[6][1]);
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
    menu.SetTitle("%T", "Spells Menu Title", client);
    menu.ExitBackButton = true;

    //We have data stored in player name to access it here
    char name[PLATFORM_MAX_PATH];
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
            Format(name, sizeof(name), "%T (%d)", spellNames[i-7], client, count);
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
            Format(name, sizeof(name), "%T (%d)", spellNames[i-7], client, count);
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
    menu.SetTitle("%T", "Abilities Menu Title", client);
    menu.ExitBackButton = true;

    //We have data stored in player name to access it here
    char name[PLATFORM_MAX_PATH];
    char infos[31][8];
    GetEntPropString(client, Prop_Data, "m_iName", name, sizeof(name));
    ExplodeString(name, "_", infos, sizeof(infos), sizeof(infos[]));
    
    int added = 0;

    if(GetClientTeam(client) == 3)
    {
        if(infos[27][2] == '1')
        {
            Format(name, sizeof(name), "%T", "Crystal Blessing", client);
            menu.AddItem("cb", name, ITEMDRAW_DISABLED);
            added++;
        }
        if(infos[28][2] == '1')
        {
            Format(name, sizeof(name), "%T", "Flame Blessing", client);
            menu.AddItem("fb", name, ITEMDRAW_DISABLED);
            added++;
        }
        if(infos[29][2] == '1')
        {
            Format(name, sizeof(name), "%T", "Soul Of The Bladekeeper", client);
            menu.AddItem("sb", name, ITEMDRAW_DISABLED);
            added++;
        }
    }
    else if(GetClientTeam(client) == 2)
    {
        if(infos[30][2] == '1')
        {
            Format(name, sizeof(name), "%T", "Corruption Shields", client);
            menu.AddItem("cs", name, ITEMDRAW_DISABLED);
            added++;
        }
    }

    if(added == 0)
    {
        Format(name, sizeof(name), "%T", "None", client);
        menu.AddItem("none", name, ITEMDRAW_DISABLED);
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
    menu.SetTitle("%T", "Lore Menu Title", client);
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
    char temp[8];
    for(int i = 0; i < 5; i++)
    {
        if(name[i] == '1')
        {
            Format(temp, sizeof(temp), "Lore%d", i+1);
        }
        else
        {
            Format(temp, sizeof(temp), "????");
        }
        Format(buffer, sizeof(buffer), "%T", temp, client);
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
    menu.SetTitle("%T", "Lore Menu Title", client);
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
    char temp[8];
    for(int i = 5; i < 9; i++)
    {
        if(name[i] == '1')
        {
            Format(temp, sizeof(temp), "Lore%d", i+1);
        }
        else
        {
            Format(temp, sizeof(temp), "????");
        }
        Format(buffer, sizeof(buffer), "%T", temp, client);
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

    menu.SetTitle("%T", "Stats Info Title", client);

    char buffer[128];

    Format(buffer, sizeof(buffer), "%T", "Damage Info", client);
    menu.AddItem("Damage", buffer, ITEMDRAW_DISABLED);

    Format(buffer, sizeof(buffer), "%T", "Resistance Info", client);
    menu.AddItem("Resistance", buffer, ITEMDRAW_DISABLED);

    Format(buffer, sizeof(buffer), "%T", "Speed Info", client);
    menu.AddItem("Speed", buffer, ITEMDRAW_DISABLED);

    Format(buffer, sizeof(buffer), "%T", "Intellect Info", client);
    menu.AddItem("Intellect", buffer, ITEMDRAW_DISABLED);

    Format(buffer, sizeof(buffer), "%T", "Luck Info", client);
    menu.AddItem("Luck", buffer, ITEMDRAW_DISABLED);

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

public void CreateResetMenu(int client)
{
    char buffer[32];

    Menu menu = CreateMenu(ResetMenuHandler);
    menu.ExitBackButton = true;
    menu.ExitButton = true;
    menu.SetTitle("%T", "Reset Are You Sure", client);
    
    Format(buffer, sizeof(buffer), "%T", "Yes", client);
    menu.AddItem("y", buffer);

    Format(buffer, sizeof(buffer), "%T", "No", client);
    menu.AddItem("n", buffer);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int ResetMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char item[32];
            GetMenuItem(menu, param2, item, sizeof(item));

            if(StrEqual(item, "y"))
            {
                SetVariantString("PluginResetPoints();");
                AcceptEntityInput(g_iCommandManager, "RunScriptCode", param1);

                CreateTimer(0.1, Timer_CreateMainMenu, GetClientUserId(param1));
            }
            else
            {
                CreateMainMenu(param1);
            }
        }
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) CreateMainMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}