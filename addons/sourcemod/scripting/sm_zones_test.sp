new bool:InCustomZone[MAXPLAYERS + 1];

public Plugin:myinfo =
{
	name        = "SM Zones Custom Punishment Test",
	author      = "Root",
	description = "Testsuite for global Zones forwards",
	version     = "1.0",
	url         = "http://www.dodsplugins.com/"
}

public OnClientPutInServer(client)
{
	InCustomZone[client] = false;
}

public Action:OnEnteredProtectedZone(client, const String:prefix)
{
	if (1 <= client <= MaxClients)
	{
		InCustomZone[client] = true;
		PrintToChatAll("%sYou have entered custom zone.", prefix);
	}
}

public Action:OnLeftProtectedZone(client, const String:prefix)
{
	if (1 <= client <= MaxClients)
	{
		InCustomZone[client] = false;

		// It's also called whenever player dies within a zone, so dont show a message if player died there
		if (IsPlayerAlive(cleint))
			PrintToChatAll("%sYou have left custom zone.", prefix);
	}
}