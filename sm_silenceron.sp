#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define NAME "[CS:S]sm_silenceron"
#define AUTHOR "BallGanda"
#define DESCRIPTION "Weapons that have silencers come with them on"
#define PLUGIN_VERSION "0.0.b1"
#define URL "https://github.com/Ballganda/SourceMod-sm_silenceron"

public Plugin myinfo = {
	name = NAME,
	author = AUTHOR,
	description = DESCRIPTION,
	version = PLUGIN_VERSION,
	url = URL
}

public void OnPluginStart() {
	
	CheckGameVersion();
		
	CreateConVar("sm_silenceron_version", PLUGIN_VERSION, NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_cvEnabled = CreateConVar("sm_silenceron_enable", "1", "sm_give Enables the plugin <1|0>");
	
	AutoExecConfig(true, "sm_silenceron");
}

public OnEntityCreated(entity, char classname[])
{
	if(g_cvEnabled.BoolValue && StrContains(classname, "weapon_")) 
	{
		char item[MAX_NAME_LENGTH];
		item[0] = NULL_STRING;
		GetEdictClassname(entity, item, sizeof(item));
		if ((StrEqual(item, "weapon_m4a1") || StrEqual(item, "weapon_usp")))
		{
			SetEntProp(entity, Prop_Send, "m_bSilencerOn", 1);
			SetEntProp(entity, Prop_Send, "m_weaponMode", 1);
		}
	}
}

public void CheckGameVersion()
{
	if(GetEngineVersion() != Engine_CSS)
	{
		SetFailState("Only CS:S Supported");
	}
}

public void About(int client)
{
	PrintToConsole(client, "");
	PrintToConsole(client, "Plugin Name.......: %s", NAME);
	PrintToConsole(client, "Plugin Author.....: %s", AUTHOR);
	PrintToConsole(client, "Plugin Description: %s", DESCRIPTION);
	PrintToConsole(client, "Plugin Version....: %s", PLUGIN_VERSION);
	PrintToConsole(client, "Plugin URL........: %s", URL);
}
