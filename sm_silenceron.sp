#include <sourcemod>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define NAME "[CS:S]sm_silenceron"
#define AUTHOR "BallGanda, and help from Addie + rest of AM discord channel"
#define DESCRIPTION "Weapons that have silencers come with them on"
#define PLUGIN_VERSION "0.0.b2"
#define URL "https://github.com/Ballganda/SourceMod-sm_silenceron"

ConVar g_cvEnablePlugin = null;

public void OnPluginStart() {
	
	CheckGameVersion();
	
	RegAdminCmd("sm_silenceron", smAbout, ADMFLAG_BAN, "sm_silenceron info in console");

	CreateConVar("sm_silenceron_version", PLUGIN_VERSION, NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_cvEnablePlugin = CreateConVar("sm_silenceron_enable", "1", "sm_silenceron Enables the plugin <1|0>", _, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "sm_silenceron");
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_cvEnablePlugin.BoolValue) 
	{
        return;
    }

    if (StrEqual(classname, "weapon_m4a1") || StrEqual(classname, "weapon_usp"))
	{
        SDKHook(entity, SDKHook_SpawnPost, OnSpawnPost);
    }
}

void OnSpawnPost(int entity)
{
    SetEntProp(entity, Prop_Send, "m_bSilencerOn", 1);
	//Sound fix by setting mode...so I was told
    SetEntProp(entity, Prop_Send, "m_weaponMode", 1);
}

public void CheckGameVersion()
{
	if(GetEngineVersion() != Engine_CSS)
	{
		SetFailState("Only CS:S Supported");
	}
}

public Plugin myinfo = {
	name = NAME,
	author = AUTHOR,
	description = DESCRIPTION,
	version = PLUGIN_VERSION,
	url = URL
}

public Action smAbout(int client, int args)
{
	PrintToConsole(client, "");
	PrintToConsole(client, "Plugin Name.......: %s", NAME);
	PrintToConsole(client, "Plugin Author.....: %s", AUTHOR);
	PrintToConsole(client, "Plugin Description: %s", DESCRIPTION);
	PrintToConsole(client, "Plugin Version....: %s", PLUGIN_VERSION);
	PrintToConsole(client, "Plugin URL........: %s", URL);
	PrintToConsole(client, "List of cvars: ");
	PrintToConsole(client, "sm_silenceron_version");
	PrintToConsole(client, "sm_silenceron_enable <1|0>");
	return Plugin_Continue;
}
