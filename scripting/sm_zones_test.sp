public Plugin:myinfo =
{
	name        = "SM Zones Custom Punishment Test",
	author      = "Root",
	description = "Testsuite for global Zones forwards",
	version     = "1.0",
	url         = "http://www.dodsplugins.com/"
}

public Action:OnEnteredProtectedZone(client, const String:name[], const String:prefix[])
{
	static Handle:ShowZones   = INVALID_HANDLE;
	if (!ShowZones) ShowZones = FindConVar("sm_zones_show_messages");

	if (1 <= client <= MaxClients)
	{
		if (GetConVarBool(ShowZones))
		{
			PrintToChat(client, "%sYou have entered \"%s\" zone.", prefix, name);
		}
	}
}

public Action:OnLeftProtectedZone(client, const String:name[], const String:prefix[])
{
	static Handle:ShowZones   = INVALID_HANDLE;
	if (!ShowZones) ShowZones = FindConVar("sm_zones_show_messages");

	if (1 <= client <= MaxClients)
	{
		// It's also called whenever player dies within a zone, so dont show a message if player died there
		if (GetConVarBool(ShowZones) && IsPlayerAlive(client))
		{
			PrintToChat(client, "%sYou have left \"%s\" zone.", prefix, name);
		}
	}
}