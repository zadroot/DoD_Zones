#pragma newdecls required

public Plugin myinfo = 
{
	name = "SM Zones Custom Punishment Test", 
	author = "Root", 
	description = "Testsuite for global Zones forwards", 
	version = "1.0", 
	url = "http://www.dodsplugins.com/"
}

public Action OnEnteredProtectedZone(int zone, int client, const char[] prefix)
{
	static Handle ShowZones = INVALID_HANDLE;
	if (!ShowZones)ShowZones = FindConVar("sm_zones_show_messages");
	
	if (1 <= client <= MaxClients)
	{
		char m_iName[MAX_NAME_LENGTH * 2];
		GetEntPropString(zone, Prop_Data, "m_iName", m_iName, sizeof(m_iName));
		
		// Skip the first 8 characters of zone name to avoid comparing the "sm_zone " prefix.
		if (StrEqual(m_iName[8], "test", false))
		{
			if (GetConVarBool(ShowZones))
			{
				PrintToChat(client, "%sYou have entered \"%s\" zone.", prefix, m_iName[8]);
			}
		}
	}
}

public Action OnLeftProtectedZone(int zone, int client, char[] prefix)
{
	static Handle ShowZones = INVALID_HANDLE;
	if (!ShowZones)ShowZones = FindConVar("sm_zones_show_messages");
	
	if (1 <= client <= MaxClients)
	{
		char m_iName[MAX_NAME_LENGTH * 2];
		GetEntPropString(zone, Prop_Data, "m_iName", m_iName, sizeof(m_iName));
		
		if (StrEqual(m_iName[8], "test", false))
		{
			// It's also called whenever player dies within a zone, so dont show a message if player died there
			if (GetConVarBool(ShowZones) && IsPlayerAlive(client))
			{
				PrintToChat(client, "%sYou have left \"%s\" zone.", prefix, m_iName[8]);
			}
		}
	}
} 