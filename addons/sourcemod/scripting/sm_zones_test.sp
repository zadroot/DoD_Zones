public Plugin:myinfo =
{
	name        = "SM Zones Custom Punishment Test",
	author      = "Root",
	description = "Testsuite for global Zones forwards",
	version     = "1.0",
	url         = "http://www.dodsplugins.com/"
}

public Action:OnEnteredProtectedZone(client, const String:prefix[])
{
	if (1 <= client <= MaxClients)
	{
		PrintToChatAll("%sYou have entered custom zone.", prefix);
	}
}

public Action:OnLeftProtectedZone(client, const String:prefix[])
{
	if (1 <= client <= MaxClients)
	{
		// It's also called whenever player dies within a zone, so dont show a message if player died there
		if (IsPlayerAlive(cleint))
			PrintToChatAll("%sYou have left custom zone.", prefix);
	}
}