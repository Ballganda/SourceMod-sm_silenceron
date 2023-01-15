public OnEntityCreated(entity, char classname[])
{
	if(StrContains(classname, "weapon_")) 
	{
    char item[max_name_length];
    item[0] = null_string;
	  GetEdictClassname(entity, item, sizeof(item));
	  if ((StrEqual(item, "weapon_m4a1") || StrEqual(item, "weapon_usp")))
    {
		SetEntProp(entity, Prop_Send, "m_bSilencerOn", 1);
		SetEntProp(entity, Prop_Send, "m_weaponMode", 1);
    }
	}
}
