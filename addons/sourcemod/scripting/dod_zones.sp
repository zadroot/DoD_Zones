/**
* DoD:S Zones by Root
*
* Description:
*   Defines zones with different punishments where players are enter.
*
* Version 1.1
* Changelog & more info at http://goo.gl/4nKhJ
*/

#pragma semicolon 1

// ====[ INCLUDES ]==========================================================
#include <sdktools>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <sdkhooks>
#include <adminmenu>

// ====[ CONSTANTS ]=========================================================
#define PLUGIN_NAME      "DoD:S Zones"
#define PLUGIN_VERSION   "1.1"

#define INIT             -1
#define EF_NODRAW        0x020
#define SLOT_MELEE       2
#define DOD_MAXPLAYERS   33
#define DOD_MAXWEAPONS   47
#define DEFAULT_INTERVAL 5.0
#define ZONES_MODEL      "models/error.mdl"
#define PREFIX           "\x04[DoD:S Zones]\x01 >> \x07FFFF00"

enum
{
	NO_POINT,
	FIRST_POINT,
	SECOND_POINT,

	POINTS_SIZE
}

enum
{
	NO_VECTOR,
	FIRST_VECTOR,
	SECOND_VECTOR,

	VECTORS_SIZE
}

enum
{
	DEFAULT_PUNISHMENT = -1,
	CUSTOM,
	ANNOUNCE,
	BOUNCE,
	SLAY,
	NOSHOOT,
	MELEE,

	PUNISHMENTS_SIZE
}

enum
{
	TEAM_ALL,
	TEAM_SPECTATOR,
	TEAM_ALLIES,
	TEAM_AXIS,

	TEAM_SIZE
}

// ====[ VARIABLES ]=========================================================
new	Handle:AdminMenuHandle  = INVALID_HANDLE,
	Handle:ZonesArray       = INVALID_HANDLE,
	Handle:zones_enabled    = INVALID_HANDLE,
	Handle:zones_punishment = INVALID_HANDLE,
	Handle:admin_immunity   = INVALID_HANDLE,
	Handle:show_zones       = INVALID_HANDLE;

// ====[ GLOBALS ]===========================================================
new	EditingZone[DOD_MAXPLAYERS + 1]      = { INIT,  ... },
	EditingVector[DOD_MAXPLAYERS + 1]    = { INIT,  ... },
	ZonePoint[DOD_MAXPLAYERS + 1]        = { false, ... },
	bool:PressedUse[DOD_MAXPLAYERS + 1]  = { false, ... },
	bool:NamesZone[DOD_MAXPLAYERS + 1]   = { false, ... },
	bool:RenamesZone[DOD_MAXPLAYERS + 1] = { false, ... },
	bool:BlockFiring[DOD_MAXPLAYERS + 1] = { false, ... },
	Float:FirstZoneVector[DOD_MAXPLAYERS + 1][3],
	Float:SecondZoneVector[DOD_MAXPLAYERS + 1][3];

new	m_hMyWeapons,
	m_flNextPrimaryAttack,
	m_flNextSecondaryAttack,
	LaserMaterial = INIT,
	HaloMaterial  = INIT,
	GlowSprite    = INIT,
	String:map[64],
	TeamZones[TEAM_SIZE];

// ====[ PLUGIN ]============================================================
public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root (based on \"Anti Rush\" plugin by Jannik 'Peace-Maker' Hartung)",
	description = "Defines zones with different punishments where players are enter",
	version     = PLUGIN_VERSION,
	url         = "http://www.dodsplugins.com/, http://www.wcfan.de/"
}


/* AskPluginLoad2()
 *
 * Called before plugin starts.
 * -------------------------------------------------------------------------- */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Makes SDKHooks as optional
	MarkNativeAsOptional("SDKHook");
	return APLRes_Success;
}

/**
 * --------------------------------------------------------------------------
 *     ____           ______                  __  _
 *    / __ \____     / ____/__  ______  _____/ /_(_)____  ____  _____
 *   / / / / __ \   / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *  / /_/ / / / /  / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *  \____/_/ /_/  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * --------------------------------------------------------------------------
*/

/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */
public OnPluginStart()
{
	// I'd use Peace-Maker's "Anti-Rush" version ConVar, but if I will do that, plugin will not be approved
	CreateConVar("dod_zones_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);

	zones_enabled    = CreateConVar("dod_zones_enable",         "1", "Whether or not enable Zones plugin", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	zones_punishment = CreateConVar("dod_zones_punishment",     "2", "Determines how plugin should handle players who entered a zone (by default):\n1 = Announce in chat\n2 = Bounce back\n3 = Slay\n4 = Dont allow to shoot\n5 = Allow only melee weapon", FCVAR_PLUGIN, true, 1.0, true, 5.0);
	admin_immunity   = CreateConVar("dod_zones_admin_immunity", "0", "Whether or not allow admins to across zones without any punishments and notificaions", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	show_zones       = CreateConVar("dod_zones_show",           "0", "Whether or not always show the zones on a map", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	// Needed to name or rename a zone
	AddCommandListener(Command_Chat, "say");
	AddCommandListener(Command_Chat, "say_team");

	// Fix for No Shoot punishment
	AddCommandListener(Command_Drop, "drop");

	// Register admin commands, which is requires config flag to use
	RegAdminCmd("sm_zones",     Command_SetupZones,     ADMFLAG_CONFIG, "Opens zones main menu");
	RegAdminCmd("sm_actzone",   Command_ActivateZone,   ADMFLAG_CONFIG, "Activates a zone (by name)");
	RegAdminCmd("sm_diactzone", Command_DiactivateZone, ADMFLAG_CONFIG, "Diactivates a zone (by name)");

	// Hook events
	HookEvent("player_death",    OnPlayerDeath);
	HookEvent("dod_round_start", OnRoundStart, EventHookMode_PostNoCopy);

	// Load plugin translations
	LoadTranslations("common.phrases");
	LoadTranslations("playercommands.phrases");
	LoadTranslations("dod_zones.phrases");

	// Adminmenu integration
	new Handle:topmenu = INVALID_HANDLE;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}

	// Finds a networkable send property offset for "CBasePlayer::m_hMyWeapons"
	if ((m_hMyWeapons = FindSendPropOffs("CBasePlayer", "m_hMyWeapons")) == -1)
	{
		SetFailState("Fatal Error: Unable to find prop offset \"CBasePlayer::m_hMyWeapons\" !");
	}

	// Also find appropriate networkable send property offsets for a weapons
	if ((m_flNextPrimaryAttack = FindSendPropOffs("CBaseCombatWeapon", "m_flNextPrimaryAttack")) == -1)
	{
		SetFailState("Fatal Error: Unable to find prop offset \"CBaseCombatWeapon::m_flNextPrimaryAttack\" !");
	}
	if ((m_flNextSecondaryAttack = FindSendPropOffs("CBaseCombatWeapon", "m_flNextSecondaryAttack")) == -1)
	{
		// Disable plugin if offset was not found
		SetFailState("Fatal Error: Unable to find prop offset \"CBaseCombatWeapon::m_flNextSecondaryAttack\" !");
	}

	// Create a global array
	ZonesArray = CreateArray();

	// And create/load plugin's config
	AutoExecConfig(true, "dod_zones");
}

/* OnAdminMenuReady()
 *
 * Called when the admin menu is ready to have items added.
 * -------------------------------------------------------------------------- */
public OnAdminMenuReady(Handle:topmenu)
{
	// Block menu handle from being called more than once
	if (topmenu == AdminMenuHandle)
	{
		return;
	}

	AdminMenuHandle = topmenu;

	// If the category is third party, it will have its own unique name
	new TopMenuObject:server_commands = FindTopMenuCategory(AdminMenuHandle, ADMINMENU_SERVERCOMMANDS);

	if (server_commands == INVALID_TOPMENUOBJECT)
	{
		// Error!
		return;
	}

	// Add 'Setup Zones' category to "ServerCommands" menu
	AddToTopMenu(AdminMenuHandle, "dod_zones", TopMenuObject_Item, AdminMenu_Zones, server_commands, "dod_zones_immunity", ADMFLAG_CONFIG);
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public OnMapStart()
{
	// Get current map
	decl String:curmap[64];
	GetCurrentMap(curmap, sizeof(curmap));

	// Set global string same as current map one
	strcopy(map, sizeof(map), curmap);

	// Initialize effects
	LaserMaterial = PrecacheModel("materials/sprites/laser.vmt");
	HaloMaterial  = PrecacheModel("materials/sprites/halo01.vmt");
	GlowSprite    = PrecacheModel("sprites/blueglow2.vmt", true);

	// Non-brush model - but we need to change model for zones
	PrecacheModel(ZONES_MODEL, true);

	// Prepare config for new map
	ParseZoneConfig();

	// Create global repeatable timer to show zones
	CreateTimer(DEFAULT_INTERVAL, Timer_ShowZones, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

/* OnClientPutInServer()
 *
 * Called when a client is entering the game.
 * -------------------------------------------------------------------------- */
public OnClientPutInServer(client)
{
	// Optionally hook some weapon forwards for knife only punishment
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponUsage);
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponUsage);
	SDKHook(client, SDKHook_WeaponEquip,  OnWeaponUsage);
}

/* OnClientDisconnect()
 *
 * When a client disconnects from the server.
 * -------------------------------------------------------------------------- */
public OnClientDisconnect(client)
{
	// Reset everything for this client
	ZonePoint[client]   = NO_POINT;
	EditingZone[client] = EditingVector[client] = INIT;

	PressedUse[client]  =
	NamesZone[client]   =
	RenamesZone[client] =
	BlockFiring[client] = false;
}

/* OnPlayerRunCmd()
 *
 * When a clients movement buttons are being processed.
 * -------------------------------------------------------------------------- */
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	// Make sure player is pressing +USE button
	if (buttons & IN_USE)
	{
		// Also check if player is about to create new zones
		if (!PressedUse[client] && ZonePoint[client] != NO_POINT)
		{
			decl Float:origin[3];
			GetClientAbsOrigin(client, origin);

			// Player is creating a zone
			if (ZonePoint[client] == FIRST_POINT)
			{
				// Set point to second on first pressing
				ZonePoint[client] = SECOND_POINT;
				FirstZoneVector[client][0] = origin[0];
				FirstZoneVector[client][1] = origin[1];
				FirstZoneVector[client][2] = origin[2];

				// Notify client
				PrintToChat(client, "%s%t", PREFIX, "Zone Edge");
			}
			else if (ZonePoint[client] == SECOND_POINT)
			{
				// Player is creating second point now
				ZonePoint[client] = NO_POINT;
				SecondZoneVector[client][0] = origin[0];
				SecondZoneVector[client][1] = origin[1];
				SecondZoneVector[client][2] = origin[2];

				// Notify client and set name boolean to 'true' to hook say/say_team commands in future usage
				PrintToChat(client, "%s%t", PREFIX, "Type Zone Name");
				NamesZone[client] = true;
			}
		}

		// Cooldown
		PressedUse[client] = true;
	}

	// Otherwise player is not pressing USE button
	else PressedUse[client] = false;
}

/* OnRoundStart()
 *
 * Called when the round starts.
 * -------------------------------------------------------------------------- */
public OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Plugin is enabled?
	if (GetConVarBool(zones_enabled))
	{
		// Kill all previous zones
		decl String:class[64], i;
		for (i = MaxClients; i < GetMaxEntities(); i++)
		{
			if (IsValidEntity(i)
			&& GetEdictClassname(i, class, sizeof(class))
			&& StrEqual(class, "trigger_multiple", false)
			&& GetEntPropString(i, Prop_Data, "m_iName", class, sizeof(class))
			&& StrContains(class, "dod_zone") != -1)
			{
				// Faster and better in round_start case, when zones are about to be recreated
				AcceptEntityInput(i, "Kill");
			}
		}

		// Then re-create X zones depends on array size
		for (new j = 0; j < GetArraySize(ZonesArray); j++)
		{
			SpawnZone(j);
		}
	}
}

/* OnPlayerDeath()
 *
 * Called when the player dies.
 * -------------------------------------------------------------------------- */
public OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	// Allow player to use any weapon again
	BlockFiring[GetClientOfUserId(GetEventInt(event, "userid"))] = false;
}

/* OnTouch()
 *
 * Called when the player touches a zone.
 * -------------------------------------------------------------------------- */
public OnTouch(const String:output[], caller, activator, Float:delay)
{
	if (GetConVarBool(zones_enabled))
	{
		// Ignore invalid activators
		if (activator > 0 && activator <= MaxClients)
		{
			// Ignore dead
			if (IsPlayerAlive(activator))
			{
				// Ignore admins if those got an immunity
				if (GetConVarBool(admin_immunity) && CheckCommandAccess(activator, "dod_zones_immunity", ADMFLAG_CONFIG, true))
				{
					return;
				}

				// Get the name a zone
				decl String:targetname[256], String:ZoneName[64];
				GetEntPropString(caller, Prop_Data, "m_iName", targetname, sizeof(targetname));

				// Initialize punishments
				new punishment = INIT;
				new real_punishment = GetConVarInt(zones_punishment);

				// Check whether or not that was StartTouch
				new bool:StartTouch = StrEqual(output, "OnStartTouch", false);

				// Loop through all available zones
				for (new i = 0; i < GetArraySize(ZonesArray); i++)
				{
					new Handle:hZone = GetArrayCell(ZonesArray, i);
					GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));

					// Ignore 'dod_zone ' prefix and check what zone we touched
					if (StrEqual(ZoneName, targetname[9], false))
					{
						// Then retrieve team and punishment
						new team   = GetArrayCell(hZone, 3);
						punishment = GetArrayCell(hZone, 4);
						if (team != TEAM_ALL && GetClientTeam(activator) != team)
						{
							// If team doesnt match, skip punishments
							return;
						}
					}
				}

				// If any punishment is used, set a real punishment value
				if (punishment > CUSTOM)
				{
					real_punishment = punishment;
				}

				switch (real_punishment)
				{
					// Just tell everybody
					case ANNOUNCE: if (StartTouch) PrintToChatAll("%s%t", PREFIX, "Player Entered Zone", activator, targetname[9]);
					case BOUNCE:
					{
						if (StartTouch)
						{
							// Bounce actovator back
							decl Float:vel[3];

							vel[0] = GetEntPropFloat(activator, Prop_Send, "m_vecVelocity[0]");
							vel[1] = GetEntPropFloat(activator, Prop_Send, "m_vecVelocity[1]");
							vel[2] = GetEntPropFloat(activator, Prop_Send, "m_vecVelocity[2]");

							vel[0] *= -2.0;
							vel[1] *= -2.0;

							// Always bounce back with at least 200 velocity
							if (vel[1] > 0.0 && vel[1] < 200.0)
								vel[1] = 200.0;
							else if (vel[1] < 0.0 && vel[1] > -200.0)
								vel[1] = -200.0;
							if (vel[2] > 0.0) // Never push the activator up!
								vel[2] *= -1.0;

							TeleportEntity(activator, NULL_VECTOR, NULL_VECTOR, vel);

							// Notify player about not allowing to enter there by default phrase from resources
							PrintHintText(activator, "#Dod_wrong_way");
						}
					}
					case SLAY:
					{
						if (StartTouch)
						{
							PrintToChatAll("%s%t", PREFIX, "Player Slayed", activator, targetname[9]);
							ForcePlayerSuicide(activator);
						}
					}
					case NOSHOOT:
					{
						// Check if player has entered a zone
						if (StartTouch)
						{
							// Notify player that he is not allowed to shoot
							PrintToChat(activator, "%s%t", PREFIX, "Cant shoot");
							BlockFiring[activator] = true;
						}
						else // Nope - player left
						{
							PrintToChat(activator, "%s%t", PREFIX, "Can shoot");
							BlockFiring[activator] = false;
						}

						// 47 offsets are available in m_hMyWeapons table
						for (new i = 0; i <= DOD_MAXWEAPONS; i++)
						{
							// Retrieve the all weapons of a player
							new weapons = GetEntDataEnt2(activator, m_hMyWeapons + (i * 4));

							// Make sure its valid
							if (weapons != -1)
							{
								if (StartTouch)
								{
									// Then dont allow player to shoot by those weapons
									SetEntDataFloat(weapons, m_flNextPrimaryAttack,   GetGameTime() + 999.9);
									SetEntDataFloat(weapons, m_flNextSecondaryAttack, GetGameTime() + 999.9);
								}
								else
								{
									// Otherwise if player left a zone - allow shooting
									SetEntDataFloat(weapons, m_flNextPrimaryAttack,   GetGameTime());
									SetEntDataFloat(weapons, m_flNextSecondaryAttack, GetGameTime());
								}
							}
						}
					}
					case MELEE: // Only allow the usage of the melee weapons
					{
						if (StartTouch)
						{
							// Manually change player's weapon to melee
							new weapon = GetPlayerWeaponSlot(activator, SLOT_MELEE);
							if (IsValidEntity(weapon))
							{
								decl String:class[24];
								GetEdictClassname(weapon, class, sizeof(class));
								FakeClientCommand(activator, "use %s", class);
								// SetEntPropEnt(activator, Prop_Data, "m_hActiveWeapon", weapon);
							}

							PrintToChat(activator, "%s%t", PREFIX, "Can use melee");

							// Respecitvitely set boolean for weapon usage
							BlockFiring[activator] = true;
						}
						else
						{
							// When player leaves this zone (usually OnEndTouch callback is fired), allow other weapons usage and notify player
							PrintToChat(activator, "%s%t", PREFIX, "Can use any weapon");
							BlockFiring[activator] = false;
						}
					}
					default:
					{
						//custom punishment will be inserted later
					}
				}
			}
		}
	}
}

/* OnWeaponUsage()
 *
 * Called when the player uses specified weapon.
 * -------------------------------------------------------------------------- */
public Action:OnWeaponUsage(client, weapon)
{
	// Block weapon usage if player is punished, otherwise use weapons as usual
	return (BlockFiring[client] && IsValidEntity(weapon)) ? Plugin_Handled : Plugin_Continue;
}


/**
 * --------------------------------------------------------------------------
 *     ______                                          __
 *    / ____/___  ____ ___  ____ ___  ____ _____  ____/ /____
 *   / /   / __ \/ __ `__ \/ __ `__ \/ __ `/ __ \/ __  / ___/
 *  / /___/ /_/ / / / / / / / / / / / /_/ / / / / /_/ (__  )
 *  \____/\____/_/ /_/ /_/_/ /_/ /_/\__,_/_/ /_/\__,_/____/
 *
 * --------------------------------------------------------------------------
*/

/* Command_Chat()
 *
 * When the say/say_team commands are used.
 * -------------------------------------------------------------------------- */
public Action:Command_Chat(client, const String:command[], args)
{
	// Retrieve the argument of say commands (a text)
	decl String:text[192];
	GetCmdArgString(text, sizeof(text));

	// Strip quotes
	StripQuotes(text);

	// When player is about to name a zone
	if (NamesZone[client])
	{
		// Set boolean after sending a text
		NamesZone[client] = false;

		// Or cancel renaming
		if (StrEqual(text, "!stop", false) || StrEqual(text, "!cancel", false))
		{
			PrintToChat(client, "%s%t", PREFIX, "Abort Zone Name");

			// Reset vector settings for new zone
			ClearVector(FirstZoneVector[client]);
			ClearVector(SecondZoneVector[client]);
			return Plugin_Handled;
		}

		// Show save menu after sending a name.
		ShowSaveZoneMenu(client, text);

		// Don't show new zone name in chat
		return Plugin_Handled;
	}
	else if (RenamesZone[client])
	{
		// Player is about to rename a zone
		decl String:OldZoneName[64];
		RenamesZone[client] = false;

		if (StrEqual(text, "!stop", false) || StrEqual(text, "!cancel", false))
		{
			PrintToChat(client, "%s%t", PREFIX, "Abort Zone Rename");

			// When renaming is cancelled - redraw zones menu
			ShowZoneOptionsMenu(client);
			return Plugin_Handled;
		}

		// Kill the previous zone (its really better than just renaming via config)
		KillZone(EditingZone[client]);

		new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

		// Get the old name of a zone
		GetArrayString(hZone, 0, OldZoneName, sizeof(OldZoneName));

		// And set to a new one
		SetArrayString(hZone, 0, text);

		// Re-spawn an entity again
		SpawnZone(EditingZone[client]);

		// Update the config file
		decl String:config[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

		PrintToChat(client, "%s%t", PREFIX, "Name Edited");

		// Read the config
		new Handle:kv = CreateKeyValues("Zones");
		FileToKeyValues(kv, config);
		if (!KvGotoFirstSubKey(kv))
		{
			// Whoops something wrong with a config!
			PrintToChat(client, "%sConfig file is empty. Can't edit it permanently!", PREFIX);
			CloseHandle(kv);

			// Redraw menu and discard changes
			ShowZoneOptionsMenu(client);
			return Plugin_Handled;
		}

		// Otherwise find the zone to edit
		decl String:buffer[192];
		KvGetSectionName(kv, buffer, sizeof(buffer));
		do
		{
			// Compare name to make sure we gonna edit correct zone
			KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
			if (StrEqual(buffer, OldZoneName, false))
			{
				// Write the new name in config
				KvSetString(kv, "zone_ident", text);
				break;
			}
		}
		while (KvGotoNextKey(kv));

		KvRewind(kv);
		KeyValuesToFile(kv, config);
		CloseHandle(kv);

		ShowZoneOptionsMenu(client);

		// Don't show new zone name in chat
		return Plugin_Handled;
	}

	// Otherwise use say commands as usual
	return Plugin_Continue;
}

/* Command_Drop()
 *
 * When the drop weapon commands are used.
 * -------------------------------------------------------------------------- */
public Action:Command_Drop(client, const String:command[], args)
{
	// Dont allow player to drop a weapon if No Shoot punishment is performed
	return BlockFiring[client] ? Plugin_Handled : Plugin_Continue;
}

/* Command_SetupZones()
 *
 * Shows a zones menu to a client.
 * -------------------------------------------------------------------------- */
public Action:Command_SetupZones(client, args)
{
	// Make sure valid client used a command
	if (!client)
	{
		ReplyToCommand(client, "%t", "Command is in-game only");
		return Plugin_Handled;
	}

	// Show a menu on !zones command
	ShowZonesMainMenu(client);
	return Plugin_Handled;
}

/* Command_ActivateZone()
 *
 * Activates an inactive zone.
 * -------------------------------------------------------------------------- */
public Action:Command_ActivateZone(client, args)
{
	// Once again check if server was used this command
	if (!client && args > 0)
	{
		decl String:text[64];
		GetCmdArg(1, text, sizeof(text));
		ActivateZone(text);
	}

	// Show diactivated zones menu to valid client
	ShowDiactivatedZonesMenu(client);

	return Plugin_Handled;
}

/* Command_DiactivateZone()
 *
 * Diactivates an active zone.
 * Note: Zone is just disabling, not killing zones at all.
 * -------------------------------------------------------------------------- */
public Action:Command_DiactivateZone(client, args)
{
	// Check whether or not argument (name) is sent
	if (!client && args > 0)
	{
		// If server is used a command, just diactivate zone by name
		decl String:text[64];
		GetCmdArg(1, text, sizeof(text));
		DiactivateZone(text);
	}

	ShowActivatedZonesMenu(client);

	// Block the command to prevent showing 'Unknown command' in client's console
	return Plugin_Handled;
}


/**
 * --------------------------------------------------------------------------
 *      __  ___
 *     /  |/  /___  ___  __  ________
 *    / /|_/ / _ \/ __ \/ / / // ___/
 *   / /  / /  __/ / / / /_/ /(__  )
 *  /_/  /_/\___/_/ /_/\__,_/_____/
 *
 * --------------------------------------------------------------------------
*/

/* AdminMenu_Zones()
 *
 * Shows a "Setup Zones" category in Server Commands menu.
 * -------------------------------------------------------------------------- */
public AdminMenu_Zones(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		// Display Menu selection item
		case TopMenuAction_DisplayOption:
		{
			// A name of the 'ServerCommands' category
			Format(buffer, maxlength, "%T", "Setup Zones", param);
		}
		// Call zones main menu on selection
		case TopMenuAction_SelectOption: ShowZonesMainMenu(param);
	}
}


/* ShowZonesMainMenu()
 *
 * Creates a menu handler to setup zones.
 * -------------------------------------------------------------------------- */
ShowZonesMainMenu(client)
{
	// When main menu is called, reset everything related to menu info
	EditingZone[client] = INIT;
	NamesZone[client]   = RenamesZone[client] = false;
	ZonePoint[client]   = NO_POINT;

	ClearVector(FirstZoneVector[client]);
	ClearVector(SecondZoneVector[client]);

	// Create menu with translated items
	decl String:translation[64];
	new Handle:menu = CreateMenu(Menu_Zones);

	// Set menu title
	SetMenuTitle(menu, "%T\n \n", "Setup Zones For", client, map);

	// Translate a string and add menu items
	Format(translation, sizeof(translation), "%T", "Add Zones", client);
	AddMenuItem(menu, "add_zone", translation);

	Format(translation, sizeof(translation), "%T\n \n", "Active Zones", client);
	AddMenuItem(menu, "active_zones", translation);

	// Also add Activate/Diactivate zone items
	Format(translation, sizeof(translation), "%T", "Activate Zones", client);
	AddMenuItem(menu, "activate_zones", translation);

	Format(translation, sizeof(translation), "%T", "Diactivate Zones", client);
	AddMenuItem(menu, "diactivate_zones", translation);

	// Add exit button, and display menu as long as possible
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_Zones()
 *
 * Main menu to setup zones.
 * -------------------------------------------------------------------------- */
public Menu_Zones(Handle:menu, MenuAction:action, client, param)
{
	if (action == MenuAction_Select)
	{
		decl String:info[32];

		// Retrieve info of menu item
		GetMenuItem(menu, param, info, sizeof(info));

		// Player selected 'Add Zone' menu
		if (StrEqual(info, "add_zone", false))
		{
			// Print an instruction in player's chat
			PrintToChat(client, "%s%t", PREFIX, "Add Zone Instruction");

			// Allow player to define zones by E button
			ZonePoint[client] = FIRST_POINT;
		}

		// No, maybe that was an 'Active zones' ?
		else if (StrEqual(info, "active_zones", false))
		{
			ShowActiveZonesMenu(client);
		}

		// Nope, that was 'Activate zones' item
		else if (StrEqual(info, "activate_zones", false))
		{
			ShowDiactivatedZonesMenu(client);
		}

		// If not - use latest one
		else if (StrEqual(info, "diactivate_zones", false))
		{
			// Diactivate zones
			ShowActivatedZonesMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		// Close menu handle on menu ending
		CloseHandle(menu);
	}
}


/* ShowActiveZonesMenu()
 *
 * Creates a menu handler to setup active zones.
 * -------------------------------------------------------------------------- */
ShowActiveZonesMenu(client)
{
	new Handle:menu = CreateMenu(Menu_ActiveZones);

	// Set menu title
	SetMenuTitle(menu, "%T:", "Active Zones", client);

	decl String:buffer[256], String:strnum[3];
	for (new i = 0; i < GetArraySize(ZonesArray); i++)
	{
		// Loop through all zones in array
		new Handle:hZone = GetArrayCell(ZonesArray, i);
		GetArrayString(hZone, 0, buffer, sizeof(buffer));

		// Add every zone as a menu item
		IntToString(i, strnum, sizeof(strnum));
		AddMenuItem(menu, strnum, buffer);
	}

	// Add exit button
	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_ActiveZones()
 *
 * Menu handler to select/edit active zones.
 * -------------------------------------------------------------------------- */
public Menu_ActiveZones(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[32], zone;
			GetMenuItem(menu, param, info, sizeof(info));

			// Define a zone number
			zone = StringToInt(info);

			// Store the zone index for further reference
			EditingZone[client] = zone;

			// Show zone menu
			ShowZoneOptionsMenu(client);
		}
		case MenuAction_Cancel:
		{
			// When player is pressed 'Back' button
			if (param == MenuCancel_ExitBack)
			{
				ShowZonesMainMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowActivateZonesMenuMenu()
 *
 * Creates a menu handler to setup diactivated zones.
 * -------------------------------------------------------------------------- */
ShowActivatedZonesMenu(client)
{
	new Handle:menu = CreateMenu(Menu_ActivatedZones);
	SetMenuTitle(menu, "%T:", "Diactivated Zones", client);

	// Initialize classname string to compare later
	decl String:class[64], i;
	for (i = MaxClients; i < GetMaxEntities(); i++)
	{
		// Make sure every entity is valid and called 'trigger_multiple'
		if (IsValidEntity(i)
		&& GetEdictClassname(i, class, sizeof(class))
		&& StrEqual(class, "trigger_multiple", false)
		&& GetEntPropString(i, Prop_Data, "m_iName", class, sizeof(class))
		&& StrContains(class, "dod_zone") != -1
		&& !GetEntProp(i, Prop_Data, "m_bDisabled")) // Dont add diactivated zones into menu
		{
			// Set menu title and item info same as m_iName without dod_zone prefix
			AddMenuItem(menu, class[9], class[9]);
		}
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_ActivatedZones()
 *
 * Menu handler to diactivate a zone.
 * -------------------------------------------------------------------------- */
public Menu_ActivatedZones(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select: // When item was selected
		{
			decl String:info[64];
			GetMenuItem(menu, param, info, sizeof(info));

			// Diactivate zone by info from menu item
			DiactivateZone(info);
			ShowActivatedZonesMenu(client);
		}
		case MenuAction_Cancel:
		{
			if (param == MenuCancel_ExitBack)
			{
				// Show zones main menu then
				ShowZonesMainMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowDiactivatedZonesMenu()
 *
 * Creates a menu handler to setup activated zones.
 * -------------------------------------------------------------------------- */
ShowDiactivatedZonesMenu(client)
{
	new Handle:menu = CreateMenu(Menu_DiactivatedZones);
	SetMenuTitle(menu, "%T:", "Activated Zones", client);

	decl String:class[64], i;

	// Loop through all entities on a map
	for (i = MaxClients; i < GetMaxEntities(); i++)
	{
		if (IsValidEntity(i)
		&& GetEdictClassname(i, class, sizeof(class))
		&& StrEqual(class, "trigger_multiple", false)
		&& GetEntPropString(i, Prop_Data, "m_iName", class, sizeof(class)) // Retrieve m_iName string
		&& StrContains(class, "dod_zone") != -1 // Does that contains 'dod_zone' prefix?
		&& GetEntProp(i, Prop_Data, "m_bDisabled"))
		{
			// Add every disabled zone into diactivated menu
			AddMenuItem(menu, class[9], class[9]);
		}
	}

	SetMenuExitBackButton(menu, true);

	// Display menu as long as possible
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_DiactivatedZones()
 *
 * Menu handler to activate diactivated zones.
 * -------------------------------------------------------------------------- */
public Menu_DiactivatedZones(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[64];
			GetMenuItem(menu, param, info, sizeof(info));

			// Otherwise activate a zone
			ActivateZone(info);
			ShowDiactivatedZonesMenu(client);
		}

		// When menu was cancelled, re-draw main menu (because there may be no diactivated items)
		case MenuAction_Cancel:
		{
			if (param == MenuCancel_ExitBack)
			{
				ShowZonesMainMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowZoneOptionsMenu()
 *
 * Creates a menu handler to setup zones options.
 * -------------------------------------------------------------------------- */
ShowZoneOptionsMenu(client)
{
	// Make sure player is not editing any other zone at this moment
	if (EditingZone[client] != INIT)
	{
		// Get the zone name
		decl String:ZoneName[64], String:translation[64], String:buffer[64];

		new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);
		GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));

		// Get zone team restrictions
		new team = GetArrayCell(hZone, 3);

		// Create menu handler and set menu title
		new Handle:menu = CreateMenu(Menu_ZoneOptions);
		SetMenuTitle(menu, "%T", "Manage Zone", client, ZoneName);

		// Add 7 items to main menu to edit
		Format(translation, sizeof(translation), "%T", "Edit First Point", client);
		AddMenuItem(menu, "vec1", translation);

		Format(translation, sizeof(translation), "%T", "Edit Second Point", client);
		AddMenuItem(menu, "vec2", translation);

		Format(translation, sizeof(translation), "%T", "Edit Name", client);
		AddMenuItem(menu, "zone_ident", translation);

		Format(translation, sizeof(translation), "%T", "Teleport To", client);

		// Also appripriately set info for every menu item
		AddMenuItem(menu, "teleport", translation);

		// If team is more than 0, show team names
		if (team > TEAM_ALL)
		{
			GetTeamName(team, buffer, sizeof(buffer));
		}
		else Format(buffer, sizeof(buffer), "%T", "Both", client);

		Format(translation, sizeof(translation), "%T", "Trigger Team", client, buffer);
		AddMenuItem(menu, "team", translation);

		// Retrieve a punishment
		switch (GetArrayCell(hZone, 4))
		{
			// No individual zones_punishment selected. Using default one (which is defined in ConVar)
			case DEFAULT_PUNISHMENT:
			{
				Format(buffer, sizeof(buffer), "%T", "Default", client);
			}
			case ANNOUNCE:
			{
				Format(buffer, sizeof(buffer), "%T", "Print Message", client);
			}
			case BOUNCE:
			{
				Format(buffer, sizeof(buffer), "%T", "Bounce Back", client);
			}
			case SLAY:
			{
				Format(buffer, sizeof(buffer), "%T", "Slay player", client);
			}
			case NOSHOOT:
			{
				Format(buffer, sizeof(buffer), "%T", "No shooting", client);
			}
			case MELEE:
			{
				Format(buffer, sizeof(buffer), "%T", "Only Melee", client);
			}
			default: // usually 0
			{
				// Custom punishment will be available later
				Format(buffer, sizeof(buffer), "%T", "Custom Punishment", client);
			}
		}

		// Update punishment info
		Format(translation, sizeof(translation), "%T %s", "Punishment", client, buffer);
		AddMenuItem(menu, "punishment", translation);

		// Add 'delete zone' option
		Format(translation, sizeof(translation), "%T", "Delete Zone", client);
		AddMenuItem(menu, "delete", translation);

		// Display menu and add 'Exit' button
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

/* Menu_ZoneOptions()
 *
 * Menu handler to fully edit a zone.
 * -------------------------------------------------------------------------- */
public Menu_ZoneOptions(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			// Get a config, menu item info and initialize everything else
			decl String:config[PLATFORM_MAX_PATH], String:ZoneName[64], String:info[32], Float:vec1[3], Float:vec2[3], color[4];
			GetMenuItem(menu, param, info, sizeof(info));
			BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

			// Retrieve zone which player is editing right now
			new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

			// Retrieve vectors and a name
			GetArrayArray(hZone, FIRST_VECTOR,  vec1, VECTORS_SIZE);
			GetArrayArray(hZone, SECOND_VECTOR, vec2, VECTORS_SIZE);
			GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));

			// Get the team
			new team = GetArrayCell(hZone, 3);

			// Teleport player in center of a zone if selected
			if (StrEqual(info, "teleport", false))
			{
				decl Float:origin[3];
				GetMiddleOfABox(vec1, vec2, origin);
				TeleportEntity(client, origin, NULL_VECTOR, Float:{0.0, 0.0, 0.0});

				// Redisplay the menu
				ShowZoneOptionsMenu(client);
			}
			else if (StrEqual(info, "team", false))
			{
				// When team is selected, decrease TeamZones int for a while
				switch (team)
				{
					// Both teams
					case TEAM_ALL:
					{
						TeamZones[TEAM_ALLIES]--;
						TeamZones[TEAM_AXIS]--;
					}
					case TEAM_ALLIES: TeamZones[TEAM_ALLIES]--;
					case TEAM_AXIS:   TeamZones[TEAM_AXIS]--;
				}

				team++;

				// If team is overbounding, make it as both
				if (team > TEAM_AXIS)
				{
					team = TEAM_ALL;
				}
				else if (team < TEAM_ALLIES)
				{
					// Same here, but set lowerbounds to first available team
					team = TEAM_ALLIES;
				}

				// Increase zone count on matches now
				switch (team)
				{
					case TEAM_ALL:
					{
						TeamZones[TEAM_ALLIES]++;
						TeamZones[TEAM_AXIS]++;
					}
					case TEAM_ALLIES: TeamZones[TEAM_ALLIES]++;
					case TEAM_AXIS:   TeamZones[TEAM_AXIS]++;
				}

				// Set the team in array
				SetArrayCell(hZone, 3, team);

				// Write changes into config
				new Handle:kv = CreateKeyValues("Zones");
				FileToKeyValues(kv, config);
				if (!KvGotoFirstSubKey(kv))
				{
					// wtf? Config is not available or broken? Stop function then!
					CloseHandle(kv);
					ShowZoneOptionsMenu(client);
					PrintToChat(client, "%sConfig file is empty. Can't edit it permanently!", PREFIX);
					return;
				}

				// Get the section name
				decl String:buffer[256];
				KvGetSectionName(kv, buffer, sizeof(buffer));
				do
				{
					// Does zone names is same?
					KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
					if (StrEqual(buffer, ZoneName, false))
					{
						// Don't add punishments section if no punishment is defined
						if (team == TEAM_ALL)
						{
							KvDeleteKey(kv, "restrict_team");
						}
						else KvSetNum(kv, "restrict_team", team);
						break;
					}
				}
				while (KvGotoNextKey(kv));

				// Get back to the top
				KvRewind(kv);
				KeyValuesToFile(kv, config);
				CloseHandle(kv);

				// Re-show options menu on every selection
				ShowZoneOptionsMenu(client);
			}

			// Change zone punishments
			else if (StrEqual(info, "punishment", false))
			{
				// Switch through the zones_punishments
				new real_punishment = GetArrayCell(hZone, 4);
				new max_punishment  = PUNISHMENTS_SIZE - 1;

				// Don't allow the melee only option to be chosen, since it requires sdkhooks
				if (!LibraryExists("sdkhooks"))
				{
					max_punishment = NOSHOOT;
				}

				real_punishment++;
				if (real_punishment > max_punishment)
				{
					// Re-init punishments on overbounds
					real_punishment = INIT;
				}
				else if (real_punishment < 1)
				{
					// Same here
					real_punishment = 1;
				}

				// Set punishment in array
				SetArrayCell(hZone, 4, real_punishment);

				new Handle:kv = CreateKeyValues("Zones");
				FileToKeyValues(kv, config);

				// Setup changes in config
				if (!KvGotoFirstSubKey(kv))
				{
					CloseHandle(kv);
					ShowZoneOptionsMenu(client);
					PrintToChat(client, "%sConfig file is empty. Can't edit it permanently!", PREFIX);
					return;
				}

				// Get the name of a zone in KeyValues config
				decl String:buffer[256];
				KvGetSectionName(kv, buffer, sizeof(buffer));
				do
				{
					KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
					if (StrEqual(buffer, ZoneName, false))
					{
						// Don't add punishments section if no punishment is defined
						if (real_punishment == INIT)
						{
							KvDeleteKey(kv, "punishment");
						}
						else KvSetNum(kv, "punishment", real_punishment);
						break;
					}
				}
				while (KvGotoNextKey(kv));

				KvRewind(kv);

				// Save config and close KV handle
				KeyValuesToFile(kv, config);
				CloseHandle(kv);

				ShowZoneOptionsMenu(client);
			}

			// Zone coordinates is editing
			else if (StrEqual(info, "vec1", false) || StrEqual(info, "vec2", false))
			{
				if (StrEqual(info, "vec1", false))
					 EditingVector[client] = FIRST_VECTOR;
				else EditingVector[client] = SECOND_VECTOR;

				if (IsNullVector(FirstZoneVector[client]) && IsNullVector(SecondZoneVector[client]))
				{
					// Define a color depends on team
					switch (team)
					{
						case TEAM_ALLIES: color = { 255, 0, 0, 255 };
						case TEAM_AXIS:   color = { 0, 255, 0, 255 };
						default:          color = { 255, 255, 255, 255};
					}

					// Clear vectors on every selection
					ClearVector(FirstZoneVector[client]);
					ClearVector(SecondZoneVector[client]);

					// And increase on every selection
					AddVectors(FirstZoneVector[client],  vec1, FirstZoneVector[client]);
					AddVectors(SecondZoneVector[client], vec2, SecondZoneVector[client]);
				}

				// Always show a zone box
				TE_SendBeamBoxToClient(client, FirstZoneVector[client], SecondZoneVector[client], LaserMaterial, HaloMaterial, 0, 30, 5.0, 5.0, 5.0, 2, 1.0, color, 0);

				// Highlight the currently edited edge for players editing a zone
				if (EditingVector[client] == FIRST_VECTOR)
				{
					TE_SetupGlowSprite(FirstZoneVector[client], GlowSprite, 5.0, 1.0, 100);
					TE_SendToClient(client);
				}
				else //if (EditingVector[client] == SECOND_VECTOR)
				{
					TE_SetupGlowSprite(SecondZoneVector[client], GlowSprite, 5.0, 1.0, 100);
					TE_SendToClient(client);
				}

				// Don't close vectors edit menu on every selection
				ShowZoneVectorEditMenu(client);
			}
			else if (StrEqual(info, "zone_ident", false))
			{
				// Set rename bool to deal with say/say_team callbacks
				PrintToChat(client, "%s%t", PREFIX, "Type Zone Name");
				RenamesZone[client] = true;
			}
			else if (StrEqual(info, "delete", false))
			{
				// Create confirmation panel
				new Handle:panel = CreatePanel();

				// Draw a panel with 'Yes/No' options
				decl String:buffer[256];
				Format(buffer, sizeof(buffer), "%T", "Confirm Delete Zone", client, ZoneName);
				SetPanelTitle(panel, buffer);

				Format(buffer, sizeof(buffer), "%T", "Yes", client);
				DrawPanelItem(panel, buffer);

				Format(buffer, sizeof(buffer), "%T", "No", client);
				DrawPanelItem(panel, buffer);

				// Send panel for 20 seconds
				SendPanelToClient(panel, client, Panel_Confirmation, MENU_TIME_FOREVER);

				// Close panel handler
				CloseHandle(panel);
			}
		}
		case MenuAction_Cancel:
		{
			// Set player to not editing something when menu is closed
			EditingZone[client] = EditingVector[client] = INIT;

			// Clear vectors that client has changed before
			ClearVector(FirstZoneVector[client]);
			ClearVector(SecondZoneVector[client]);

			// When client pressed 'Back' option
			if (param == MenuCancel_ExitBack)
			{
				// Show active zones menu
				ShowActiveZonesMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowZoneVectorEditMenu()
 *
 * Creates a menu handler to setup zone coordinations.
 * -------------------------------------------------------------------------- */
ShowZoneVectorEditMenu(client)
{
	// Make sure player is not editing any other zone at this moment
	if (EditingZone[client]  != INIT
	|| EditingVector[client] != INIT)
	{
		// Initialize translation string
		decl String:ZoneName[64], String:translation[64];

		// Get the zone name
		new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);
		GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));

		new Handle:menu = CreateMenu(Menu_ZoneVectorEdit);
		SetMenuTitle(menu, "%T", "Edit Zone", client, ZoneName, EditingVector[client]);

		// Add 7 items in coordinates menu
		Format(translation, sizeof(translation), "%T", "Add to X", client);
		AddMenuItem(menu, "ax", translation);

		Format(translation, sizeof(translation), "%T", "Add to Y", client);

		// Set every menu item as unique
		AddMenuItem(menu, "ay", translation);

		Format(translation, sizeof(translation), "%T", "Add to Z", client);
		AddMenuItem(menu, "az", translation);

		Format(translation, sizeof(translation), "%T", "Subtract from X", client);
		AddMenuItem(menu, "sx", translation);

		Format(translation, sizeof(translation), "%T", "Subtract from Y", client);
		AddMenuItem(menu, "sy", translation);

		Format(translation, sizeof(translation), "%T", "Subtract from Z", client);
		AddMenuItem(menu, "sz", translation);

		Format(translation, sizeof(translation), "%T", "Save", client);
		AddMenuItem(menu, "save", translation);

		// Also add 'Back' button and show menu as long as possible
		SetMenuExitBackButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
}

/* Menu_ZoneVectorEdit()
 *
 * Menu handler to edit zone coordinates/vectors.
 * -------------------------------------------------------------------------- */
public Menu_ZoneVectorEdit(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[32], color[4];
			GetMenuItem(menu, param, info, sizeof(info));

			// Save the new coordinates to the file and the array
			if (StrEqual(info, "save", false))
			{
				// The dynamic array cache
				decl String:ZoneName[64];

				new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

				// Retrieve zone name and appropriately set zone vector (client info) on every selection
				GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));
				SetArrayArray(hZone,  FIRST_VECTOR,  FirstZoneVector[client],  VECTORS_SIZE);
				SetArrayArray(hZone,  SECOND_VECTOR, SecondZoneVector[client], VECTORS_SIZE);

				// Get team
				new team = GetArrayCell(hZone, 3);

				// Change colors appropriately
				switch (team)
				{
					case TEAM_ALLIES: color = { 255, 0, 0, 255 }; // Red
					case TEAM_AXIS:   color = { 0, 255, 0, 255 }; // Green
					default:          color = { 255, 255, 255, 255}; // White
				}

				// Re-spawn zone when its saved
				KillZone(EditingZone[client]);
				SpawnZone(EditingZone[client]);

				// Notify client about saving position
				PrintToChat(client, "%s%t", PREFIX, "Saved");

				// Write changes into config file
				decl String:config[PLATFORM_MAX_PATH];
				BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

				new Handle:kv = CreateKeyValues("Zones");
				FileToKeyValues(kv, config);

				// Make sure config is valid
				if (!KvGotoFirstSubKey(kv))
				{
					CloseHandle(kv);
					ShowZoneVectorEditMenu(client);

					// Error!
					PrintToChat(client, "%sConfig file is empty. Can't edit it permanently!", PREFIX);
					return;
				}

				decl String:buffer[256];
				KvGetSectionName(kv, buffer, sizeof(buffer));

				// Go thru KV config
				do
				{
					// Set coordinates for zone
					KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
					if (StrEqual(buffer, ZoneName, false))
					{
						// Set appropriate section for KV config
						KvSetVector(kv, "coordinates 1", FirstZoneVector[client]);
						KvSetVector(kv, "coordinates 2", SecondZoneVector[client]);
						break;
					}
				}

				// Until KV is ended
				while (KvGotoNextKey(kv));

				KvRewind(kv);
				KeyValuesToFile(kv, config);
				CloseHandle(kv);
			}

			// Add X
			else if (StrEqual(info, "ax", false))
			{
				// Add to the x axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					// Move zone for 5 units on every selection
					FirstZoneVector[client][0] += 5.0;
				}
				else SecondZoneVector[client][0] += 5.0;
			}
			else if (StrEqual(info, "ay", false))
			{
				// Add to the y axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][1] += 5.0;
				}
				else SecondZoneVector[client][1] += 5.0;
			}
			else if (StrEqual(info, "az", false))
			{
				// Add to the z axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][2] += 5.0;
				}
				else SecondZoneVector[client][2] += 5.0;
			}

			// Subract X
			else if (StrEqual(info, "sx", false))
			{
				// Subtract from the x axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][0] -= 5.0;
				}
				else SecondZoneVector[client][0] -= 5.0;
			}
			else if (StrEqual(info, "sy", false))
			{
				// Subtract from the y axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][1] -= 5.0;
				}
				else SecondZoneVector[client][1] -= 5.0;
			}
			else if (StrEqual(info, "sz", false))
			{
				// Subtract from the z axis
				if (EditingVector[client] == FIRST_VECTOR)
				{
					FirstZoneVector[client][2] -= 5.0;
				}
				else SecondZoneVector[client][2] -= 5.0;
			}

			// Always show a zone box on every selection
			TE_SendBeamBoxToClient(client, FirstZoneVector[client], SecondZoneVector[client], LaserMaterial, HaloMaterial, 0, 30, 5.0, 5.0, 5.0, 2, 1.0, color, 0);

			// Highlight the currently edited edge for players editing a zone
			if (EditingVector[client] == FIRST_VECTOR)
			{
				TE_SetupGlowSprite(FirstZoneVector[client], GlowSprite, 5.0, 1.0, 100);
				TE_SendToClient(client);
			}
			else //if (EditingVector[client] == SECOND_VECTOR)
			{
				TE_SetupGlowSprite(SecondZoneVector[client], GlowSprite, 5.0, 1.0, 100);
				TE_SendToClient(client);
			}

			// Redisplay the menu
			ShowZoneVectorEditMenu(client);
		}
		case MenuAction_Cancel:
		{
			// When player is presset 'back' button
			if (param == MenuCancel_ExitBack)
			{
				// Redraw zone options menu
				ShowZoneOptionsMenu(client);
			}
			else EditingZone[client] = INIT; // When player just pressed Exit button, make sure player is not editing any zone anymore
		}
		case MenuAction_End: CloseHandle(menu);
	}
}


/* ShowSaveZoneMenu()
 *
 * Creates a menu handler to save or discard new zone.
 * -------------------------------------------------------------------------- */
ShowSaveZoneMenu(client, const String:name[])
{
	decl String:translation[64];

	// Confirm the new zone after naming
	new Handle:menu = CreateMenu(Menu_SaveZone);
	SetMenuTitle(menu, "%T", "Adding Zone", client);

	// Add 2 options to menu - Zone Name and Discard
	Format(translation, sizeof(translation), "%T", "Save", client);
	AddMenuItem(menu, name, translation);
	Format(translation, sizeof(translation), "%T", "Discard", client);
	AddMenuItem(menu, "discard", translation);

	// Dont show 'Exit' button here
	SetMenuExitButton(menu, false);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

/* Menu_SaveZone()
 *
 * Menu handler to save new created zone.
 * -------------------------------------------------------------------------- */
public Menu_SaveZone(Handle:menu, MenuAction:action, client, param)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			decl String:info[32];
			GetMenuItem(menu, param, info, sizeof(info));

			// Don't save the new zone if player pressed 'Discard' option
			if (StrEqual(info, "discard", false))
			{
				// Clear vectors
				ClearVector(FirstZoneVector[client]);
				ClearVector(SecondZoneVector[client]);

				// Notify player
				PrintToChat(client, "%s%t", PREFIX, "Discarded");
			}
			else // Save the new zone, because any other item is selected
			{
				// Save new zone in config
				decl String:config[PLATFORM_MAX_PATH];
				BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

				// Get "Zones" config
				new Handle:kv = CreateKeyValues("Zones"), number;
				FileToKeyValues(kv, config);

				decl String:buffer[256], String:strnum[5], temp;
				if (KvGotoFirstSubKey(kv))
				{
					do
					{
						// Get the highest numer and increase it by 1
						KvGetSectionName(kv, buffer, sizeof(buffer));
						temp = StringToInt(buffer);

						// Saving every zone as a number is faster and safer
						if (temp >= number)
						{
							// Set number for zone in config
							number = temp + 1;
						}

						// There is already a zone with this name
						KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
						if (StrEqual(buffer, info, false))
						{
							// Notify player about that and hook say/say_team callbacks to allow player to give new name
							PrintToChat(client, "%s%t", PREFIX, "Name Already Taken", info);
							NamesZone[client] = true;
							return;
						}
					}
					while (KvGotoNextKey(kv));
					KvGoBack(kv);
				}

				// Convert number to a string, becaue every item in KV should be quoted
				IntToString(number, strnum, sizeof(strnum));

				// Jump to zone number
				KvJumpToKey(kv, strnum, true);

				// Set name and coordinates
				KvSetString(kv, "zone_ident", info);
				KvSetVector(kv, "coordinates 1", FirstZoneVector[client]);
				KvSetVector(kv, "coordinates 2", SecondZoneVector[client]);

				// Get back to the top, save config and close KV handle again
				KvRewind(kv);
				KeyValuesToFile(kv, config);
				CloseHandle(kv);

				// Store the current vectors to the array
				new Handle:TempArray = CreateArray(ByteCountToCells(256));

				// Set the name
				PushArrayString(TempArray, info);

				// Set the first coordinates
				PushArrayArray(TempArray, FirstZoneVector[client], VECTORS_SIZE);

				// Set the second coordinates
				PushArrayArray(TempArray, SecondZoneVector[client], VECTORS_SIZE);

				// Set the team to both by default
				PushArrayCell(TempArray, 0);

				// Set the zones_punishment to default (defined by ConVar)
				PushArrayCell(TempArray, INIT);

				// Set editing zone for a player
				EditingZone[client] = PushArrayCell(ZonesArray, TempArray);

				// Spawn the trigger_multiple entity (zone)
				SpawnZone(EditingZone[client]);

				// Notify client about successfull saving
				PrintToChat(client, "%s%t", PREFIX, "Saved");

				// Show edit zone options for client
				ShowZoneOptionsMenu(client);
			}
		}
		case MenuAction_Cancel:
		{
			// When menu is ended - reset everything
			EditingZone[client] = EditingVector[client] = INIT;
			ClearVector(FirstZoneVector[client]);
			ClearVector(SecondZoneVector[client]);

			if (param == MenuCancel_ExitBack)
			{
				// If player pressed back button, show active zones menu
				ShowActiveZonesMenu(client);
			}
		}
		case MenuAction_End: CloseHandle(menu);
	}
}

/* Panel_Confirmation()
 *
 * Panel handler to confirm zone deletion.
 * -------------------------------------------------------------------------- */
public Panel_Confirmation(Handle:menu, MenuAction:action, client, param)
{
	// Client pressed a button
	if (action == MenuAction_Select)
	{
		// Pressed 'Yes'
		if (param == 1)
		{
			// Kill the trigger_multiple entity (a box)
			KillZone(EditingZone[client]);

			// Delete from cache array
			decl String:ZoneName[64];
			new Handle:hZone = GetArrayCell(ZonesArray, EditingZone[client]);

			// Close array handle
			GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));
			CloseHandle(hZone);

			// Remove info from array
			RemoveFromArray(ZonesArray, EditingZone[client]);

			// Set client zone appropriately (to INIT/UNKNOWN)
			EditingZone[client] = INIT;

			// Delete zone from config file
			decl String:config[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

			new Handle:kv = CreateKeyValues("Zones");
			FileToKeyValues(kv, config);
			if (!KvGotoFirstSubKey(kv))
			{
				// Something was wrong - stop and draw active zones again
				CloseHandle(kv);
				ShowActiveZonesMenu(client);
				return;
			}

			// Everything seems to be fine
			decl String:buffer[256];
			KvGetSectionName(kv, buffer, sizeof(buffer));
			do
			{
				// So compare zone names
				KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
				if (StrEqual(buffer, ZoneName, false))
				{
					// Delete the whole zone section on match
					KvDeleteThis(kv);
					break;
				}
			}
			while (KvGotoNextKey(kv));

			KvRewind(kv);
			KeyValuesToFile(kv, config);
			CloseHandle(kv);

			// Notify client and show active zones menu
			PrintToChat(client, "%s%t", PREFIX, "Deleted Zone", ZoneName);
			ShowActiveZonesMenu(client);
		}
		else
		{
			// Player pressed 'No' button - cancel deletion and redraw previous menu
			PrintToChat(client, "%s%t", PREFIX, "Canceled Zone Deletion");
			ShowZoneOptionsMenu(client);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		// Cancel deletion if menu was closed
		PrintToChat(client, "%s%t", PREFIX, "Canceled Zone Deletion");

		ShowZoneOptionsMenu(client);
	}

	// Since its a panel - no need to check MenuAction_End action to close handle
}


/**
 * --------------------------------------------------------------------------
 *      ______                  __  _
 *     / ____/__  ______  _____/ /_(_)____  ____  _____
 *    / /_   / / / / __ \/ ___/ __/ // __ \/ __ \/ ___/
 *   / __/  / /_/ / / / / /__/ /_/ // /_/ / / / (__  )
 *  /_/     \__,_/_/ /_/\___/\__/_/ \____/_/ /_/____/
 *
 * --------------------------------------------------------------------------
*/

/* Timer_ShowZones()
 *
 * Repeatable timer to redraw zones on a map.
 * -------------------------------------------------------------------------- */
public Action:Timer_ShowZones(Handle:timer)
{
	// Do the stuff if plugin is enabled
	if (GetConVarBool(zones_enabled))
	{
		// Get all the zones from array
		for (new i = 0; i < GetArraySize(ZonesArray); i++)
		{
			// Initialize positions, color, team index and other stuff
			decl Float:pos1[3], Float:pos2[3], color[4], Handle:hZone, team, client;
			hZone = GetArrayCell(ZonesArray, i);

			// Retrieve positions from array
			GetArrayArray(hZone, FIRST_VECTOR,  pos1, VECTORS_SIZE);
			GetArrayArray(hZone, SECOND_VECTOR, pos2, VECTORS_SIZE);

			// And a team
			team = GetArrayCell(hZone, 3);

			// Set color for zone respectivitely
			switch (team)
			{
				case TEAM_ALLIES: color = { 255, 0, 0, 255 };
				case TEAM_AXIS:   color = { 0, 255, 0, 255 };
				default:          color = { 255, 255, 255, 255};
			}

			// Loop through all clients
			for (client = 1; client <= MaxClients; client++)
			{
				if (IsClientInGame(client))
				{
					// If player is editing a zones - show all zones then
					if (EditingZone[client] != INIT)
					{
						TE_SendBeamBoxToClient(client, pos1, pos2, LaserMaterial, HaloMaterial, 0, 30, 5.0, 5.0, 5.0, 2, 1.0, color, 0);
					}
					// Otherwise always show zones if plugin is set it to true
					else if (GetConVarBool(show_zones) && (team == TEAM_ALL || (GetClientTeam(client) == team)))
					{
						// Also dont show friendly zones at all
						TE_SendBeamBoxToClient(client, pos1, pos2, LaserMaterial, HaloMaterial, 0, 30, 5.0, 5.0, 5.0, 2, 1.0, color, 0);
					}
				}
			}
		}
	}
}

/* ParseZoneConfig()
 *
 * Prepares a zones config at every map change.
 * -------------------------------------------------------------------------- */
ParseZoneConfig()
{
	// Clear previous info
	CloseHandleArray(ZonesArray);
	ClearArray(ZonesArray);

	// Get the config
	decl String:config[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, config, sizeof(config), "data/zones/%s.cfg", map);

	// Make sure config is exists
	if (FileExists(config))
	{
		// Create KeyValues handle
		new Handle:kv = CreateKeyValues("Zones");
		FileToKeyValues(kv, config);
		if (!KvGotoFirstSubKey(kv))
		{
			CloseHandle(kv);
			return;
		}

		// Initialize everything, also get the section names
		decl String:buffer[256], Handle:TempArray, Float:vector[3], zoneIndex, real_punishment;
		KvGetSectionName(kv, buffer, sizeof(buffer));

		// Go through config for this map
		do
		{
			// Create temporary array
			TempArray = CreateArray(ByteCountToCells(256));

			// Retrieve zone name, and push name into temp array
			KvGetString(kv, "zone_ident", buffer, sizeof(buffer));
			PushArrayString(TempArray, buffer);

			// Get first coordinations
			KvGetVector(kv, "coordinates 1", vector);
			PushArrayArray(TempArray, vector, VECTORS_SIZE);

			// Second coordinations
			KvGetVector(kv, "coordinates 2", vector);
			PushArrayArray(TempArray, vector, VECTORS_SIZE);

			// Get the team restrictions
			new team = KvGetNum(kv, "restrict_team", 0);
			PushArrayCell(TempArray, team);

			// Increase zone count on match
			switch(team)
			{
				// Both teams
				case TEAM_ALL:
				{
					TeamZones[TEAM_ALLIES]++;
					TeamZones[TEAM_AXIS]++;
				}
				case TEAM_ALLIES: TeamZones[TEAM_ALLIES]++;
				case TEAM_AXIS:   TeamZones[TEAM_AXIS]++;
			}

			// Get the punishments
			real_punishment = KvGetNum(kv, "punishment", DEFAULT_PUNISHMENT);

			// Reset the melee punishment for a zone to default if sdkhooks is not available
			if (!LibraryExists("sdkhooks") && real_punishment >= MELEE)
			{
				real_punishment = DEFAULT_PUNISHMENT;
			}

			// Add punishments into temporary array
			PushArrayCell(TempArray, real_punishment);

			// Get the zone index
			zoneIndex = PushArrayCell(ZonesArray, TempArray);

			// Spawn a zone each time KV got a config for
			SpawnZone(zoneIndex);
		}

		// Until keyvalues config is ended
		while (KvGotoNextKey(kv));

		// Get back to the top
		KvGoBack(kv);

		// And close KeyValues handler
		CloseHandle(kv);
	}
}

/* ActivateZone()
 *
 * Activates an inactive zone by name.
 * -------------------------------------------------------------------------- */
ActivateZone(const String:text[])
{
	decl String:class[64], i;

	// Loop through all entitys
	for (i = MaxClients; i < GetMaxEntities(); i++)
	{
		if (IsValidEntity(i)
		&& GetEdictClassname(i, class, sizeof(class))
		&& StrEqual(class, "trigger_multiple", false)
		&& GetEntPropString(i, Prop_Data, "m_iName", class, sizeof(class))
		&& StrEqual(class[9], text, false)) // Skip first 9 characters to avoid comparing with 'dod_zone %' prefix
		{
			// Found - activate a zone and break the loop (optimizations)
			AcceptEntityInput(i, "Enable");
			break;
		}
	}
}

/* DiactivateZone()
 *
 * Diactivates a zone by name.
 * -------------------------------------------------------------------------- */
DiactivateZone(const String:text[])
{
	decl String:class[64], i;

	// Entity indexes are starting at MaxClients value
	for (i = MaxClients; i < GetMaxEntities(); i++)
	{
		// Make sure the passed entity is valid
		if (IsValidEntity(i)
		&& GetEdictClassname(i, class, sizeof(class)) // Get the classname
		&& StrEqual(class, "trigger_multiple", false) // Make sure its Zone ( classname is trigger_multiple )
		&& GetEntPropString(i, Prop_Data, "m_iName", class, sizeof(class))
		&& StrEqual(class[9], text, false))
		{
			// Retrieve names of every entity, and if name contains "dod_zone" text - just disable this entity
			AcceptEntityInput(i, "Disable");
			break;
		}
	}
}

/* SpawnZone()
 *
 * Spawns a trigger_multiple entity (zone)
 * -------------------------------------------------------------------------- */
SpawnZone(zoneIndex)
{
	decl Float:middle[3], Float:m_vecMins[3], Float:m_vecMaxs[3], String:ZoneName[128];

	// Get zone index from array
	new Handle:hZone = GetArrayCell(ZonesArray, zoneIndex);
	GetArrayArray(hZone,  FIRST_VECTOR,  m_vecMins, VECTORS_SIZE);
	GetArrayArray(hZone,  SECOND_VECTOR, m_vecMaxs, VECTORS_SIZE);
	GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));

	// Create a zone (best one is trigger_multiple)
	new ent = CreateEntityByName("trigger_multiple");

	// Set spawnflags, name and other useful stuff
	DispatchKeyValue(ent, "spawnflags", "64");
	Format(ZoneName, sizeof(ZoneName), "dod_zone %s", ZoneName);
	DispatchKeyValue(ent, "targetname", ZoneName);
	DispatchKeyValue(ent, "wait", "0");

	// Spawn an entity
	DispatchSpawn(ent);

	// Since its brush entity, use ActivateEntity as well
	ActivateEntity(ent);

	// Set datamap spawnflags (value means copy origin and angles)
	SetEntProp(ent, Prop_Data, "m_spawnflags", 64);

	// Get the middle of zone
	GetMiddleOfABox(m_vecMins, m_vecMaxs, middle);

	// Move zone entity in middle of a box
	TeleportEntity(ent, middle, NULL_VECTOR, NULL_VECTOR);

	// Set the model (its required)
	SetEntityModel(ent, ZONES_MODEL);

	// Have the m_vecMins always be negative
	m_vecMins[0] = m_vecMins[0] - middle[0];
	if (m_vecMins[0] > 0.0)
		m_vecMins[0] *= -1.0;
	m_vecMins[1] = m_vecMins[1] - middle[1];
	if (m_vecMins[1] > 0.0)
		m_vecMins[1] *= -1.0;
	m_vecMins[2] = m_vecMins[2] - middle[2];
	if (m_vecMins[2] > 0.0)
		m_vecMins[2] *= -1.0;

	// And the m_vecMaxs always be positive
	m_vecMaxs[0] = m_vecMaxs[0] - middle[0];
	if (m_vecMaxs[0] < 0.0)
		m_vecMaxs[0] *= -1.0;
	m_vecMaxs[1] = m_vecMaxs[1] - middle[1];
	if (m_vecMaxs[1] < 0.0)
		m_vecMaxs[1] *= -1.0;
	m_vecMaxs[2] = m_vecMaxs[2] - middle[2];
	if (m_vecMaxs[2] < 0.0)
		m_vecMaxs[2] *= -1.0;

	// Set mins and maxs for entity
	SetEntPropVector(ent, Prop_Send, "m_vecMins", m_vecMins);
	SetEntPropVector(ent, Prop_Send, "m_vecMaxs", m_vecMaxs);

	// Make it non-solid
	SetEntProp(ent, Prop_Send, "m_nSolidType", 2);

	// Retrieve effects, remove EF_NODRAW and set effects properly (thanks Blodia!)
	new m_fEffects = GetEntProp(ent, Prop_Send, "m_fEffects");
	m_fEffects |= EF_NODRAW;
	SetEntProp(ent, Prop_Send, "m_fEffects", m_fEffects);

	// Hook StartTouch entity output
	HookSingleEntityOutput(ent, "OnStartTouch", OnTouch);
	HookSingleEntityOutput(ent, "OnEndTouch",   OnTouch);
}

/* KillZone()
 *
 * Removes a trigger_multiple entity (zone) from a world.
 * -------------------------------------------------------------------------- */
KillZone(zoneIndex)
{
	decl String:ZoneName[128], String:class[256], i;

	// Get the zone index and name of a zone
	new Handle:hZone = GetArrayCell(ZonesArray, zoneIndex);
	GetArrayString(hZone, 0, ZoneName, sizeof(ZoneName));

	// Loop through all entities on a map
	for (i = MaxClients; i < GetMaxEntities(); i++)
	{
		if (IsValidEntity(i)
		&& GetEdictClassname(i, class, sizeof(class))
		&& StrEqual(class, "trigger_multiple", false)
		&& GetEntPropString(i, Prop_Data, "m_iName", class, sizeof(class)) // Get m_iName datamap
		&& StrEqual(class[9], ZoneName, false)) // And check if m_iName is equal to name from array
		{
			// Unhook touch callback, kill an entity and break the loop
			UnhookSingleEntityOutput(i, "OnStartTouch", OnTouch);
			UnhookSingleEntityOutput(i, "OnEndTouch",   OnTouch);
			AcceptEntityInput(i, "Kill");
			break;
		}
	}
}

/**
 * --------------------------------------------------------------------------
 *      __  ___
 *     /  |/  (_)__________
 *    / /|_/ / // ___/ ___/
 *   / /  / / /(__  ) /__
 *  /_/  /_/_//____/\___/
 *
 * --------------------------------------------------------------------------
*/

/* CloseHandleArray()
 *
 * Closes active adt_array handles.
 * -------------------------------------------------------------------------- */
CloseHandleArray(Handle:adt_array)
{
	// Loop through all array handles
	for (new i = 0; i < GetArraySize(adt_array); i++)
	{
		// Retrieve cell value from array, and close it
		new Handle:hZone = GetArrayCell(adt_array, i);
		CloseHandle(hZone);
	}
}

/* ClearVector()
 *
 * Resets vector values to 0.0
 * -------------------------------------------------------------------------- */
ClearVector(Float:vec[3])
{
	vec[0] = vec[1] = vec[2] = 0.0;
}

/* IsNullVector()
 *
 * Checks whether or not given vector is reset (null).
 * -------------------------------------------------------------------------- */
bool:IsNullVector(const Float:vec[3])
{
	if (vec[0] == 0.0
	&&  vec[1] == 0.0
	&&  vec[2] == 0.0)
	{
		// All coordinates are 0.0 - vector is null
		return true;
	}

	// Otherwise not
	return false;
}

/* GetMiddleOfABox()
 *
 * Retrieves a real center of zone box.
 * -------------------------------------------------------------------------- */
GetMiddleOfABox(const Float:vec1[3], const Float:vec2[3], Float:buffer[3])
{
	// Just make vector from points and divide it by 2
	decl Float:mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);
	mid[0] = mid[0] / 2.0;
	mid[1] = mid[1] / 2.0;
	mid[2] = mid[2] / 2.0;
	AddVectors(vec1, mid, buffer);
}

/**
 * Sets up a boxed beam effect.
 *
 * Ported from eventscripts vecmath library
 *
 * @param client		The client to show the box to.
 * @param upc			One upper corner of the box.
 * @param btc			One bottom corner of the box.
 * @param ModelIndex	Precached model index.
 * @param HaloIndex		Precached model index.
 * @param StartFrame	Initital frame to render.
 * @param FrameRate		Beam frame rate.
 * @param Life			Time duration of the beam.
 * @param Width			Initial beam width.
 * @param EndWidth		Final beam width.
 * @param FadeLength	Beam fade time duration.
 * @param Amplitude		Beam amplitude.
 * @param color			Color array (r, g, b, a).
 * @param Speed			Speed of the beam.
 * @noreturn
 */
TE_SendBeamBoxToClient(client, const Float:upc[3], const Float:btc[3], ModelIndex, HaloIndex, StartFrame, FrameRate, Float:Life, Float:Width, Float:EndWidth, FadeLength, Float:Amplitude, const Color[4], Speed)
{
	// Create the additional corners of the box
	new Float:tc1[3];
	AddVectors(tc1, upc, tc1);
	tc1[0] = btc[0];
	new Float:tc2[3];
	AddVectors(tc2, upc, tc2);
	tc2[1] = btc[1];
	new Float:tc3[3];
	AddVectors(tc3, upc, tc3);
	tc3[2] = btc[2];
	new Float:tc4[3];
	AddVectors(tc4, btc, tc4);
	tc4[0] = upc[0];
	new Float:tc5[3];
	AddVectors(tc5, btc, tc5);
	tc5[1] = upc[1];
	new Float:tc6[3];
	AddVectors(tc6, btc, tc6);
	tc6[2] = upc[2];

	// Draw all the edges
	TE_SetupBeamPoints(upc, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(upc, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(upc, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, btc, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, btc, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, btc, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
}