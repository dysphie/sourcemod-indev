/**
 * TODO:
 * - move RunCmd logic inside of HealProgress
 * - sounds
 * - separate next-think for sfx/ui/use 
 * - SDKCalls
 * - opti
 */

#include <sdktools>
#include <sdkhooks>

float nextThink[MAXPLAYERS+1];

ConVar medkitTime;
ConVar bandageTime;

enum VoiceCommand
{
	VoiceCommand_Stay = 4,
	VoiceCommand_ThankYou = 5
}

enum struct ItemData
{
	Function prefunc;
	Function func;
	float useTime;

	void Init()
	{
		this.prefunc = INVALID_FUNCTION;
		this.func = INVALID_FUNCTION;
		this.useTime = -1.0;
	}
}

bool GetItemData(int item, ItemData idata)
{
	char classname[32];
	GetEntityClassname(item, classname, sizeof(classname));

	if (strcmp(classname[5], "first_aid") == 0)
	{
		PrintToServer("DEBUG: first_aid data");

		idata.prefunc = IsPlayerHurt
		idata.func = ApplyFirstAidKit;
		idata.useTime = medkitTime.FloatValue;
		return true;
	}

	if (strcmp(classname[5], "bandages") == 0)
	{
		PrintToServer("DEBUG: bandages data");

		idata.prefunc = IsPlayerBleeding
		idata.func = ApplyBandage;
		idata.useTime = bandageTime.FloatValue;
		return true;
	}

	PrintToServer("DEBUG: no valid item");
	return false;
}

enum struct HealProgress
{
	float startTime;		// Time when the healing started
	float duration;			// Time it will take to heal
	int target;				// Player being healed
	int client;				// Player doing the healing
	int item;				// Medical item being used
	ItemData itemData;		// Functions of medical item

	float pctElapsed;		// Used to play medical sounds


	/**
	 * Make struct ready for use by initializing its variables 
	 * Must be called before anything else!
	 *
	 * @param client    Client index to bind struct to.
	 */
	void Init(int client)
	{
		this.client = client;
		this.Reset();
	}

	/**
	 * Called when the client starts healing someone.
	 * 
	 * @param target    Player to start healing
	 * @param item 		Item to heal with
	 */
	void Start(int& target, int& item)
	{
		PrintToServer("DEBUG: useTime %f", this.itemData.useTime);

		this.startTime = GetTickedTime();
		this.duration = this.itemData.useTime;
		this.target = target;
		this.item = item;

		FreezePlayer(this.client);
		ShowProgressBar(this.client, this.itemData.useTime);
		DoVoiceCommand(this.client, VoiceCommand_Stay);
	}

	/**
	 * Reset the struct to its default usable state
	 *
	 * @return        The float value of the integer and float added together.
	 */
	void Reset()
	{
		this.target = -1;
		this.startTime = -1.0;
		this.duration = -1.0;
		this.pctElapsed = -1.0;
		this.item = -1;
		this.itemData.Init();
	}

	/**
	 * Called when the heal progress is successful
	 */
	void Complete()
	{
		DoVoiceCommand(this.target, VoiceCommand_ThankYou);

		// Call right function for medical item
		Call_StartFunction(INVALID_HANDLE, this.itemData.func)
		Call_PushCell(this.target); 
		Call_Finish();    
  		
		SDKHooks_DropWeapon(this.client, this.item);
		RemoveEntity(this.item);

		this.Stop();
		// TODO: Add client healed forward
	}

	/**
	 * Called when the heal progress stops, successful or not
	 */
	void Stop()
	{
		PrintCenterText(this.client, "");
		PrintToServer("Stop");
		UnfreezePlayer(this.client);
		HideProgressBar(this.client);
		this.Reset();
	}


	/**
	 * TODO
	 */
	void Think(int& target, int& item)
	{
		float curTime = GetTickedTime();

		if (this.IsActive())
		{
			// Cancel if player switched to a different target or item
			if (item != this.item || target != this.target)
			{
				this.Stop();
				return;
			}
		}

		else
		{
			if (item == -1 || target == -1)
				return;

			if (!GetItemData(item, this.itemData))
			{
				return;
			}

			// Test our target with prefunc
			bool pass;
			Call_StartFunction(INVALID_HANDLE, this.itemData.prefunc)
			Call_PushCell(target);
			Call_Finish(pass);

			if (!pass)
			{
				// TODO: Reset 
				PrintToServer("DEBUG: failed prefunc");
				return;
			}
			else {
				PrintToServer("DEBUG: prefunc ok");
			}

			this.Start(target, item);
		}

		PrintCenterText(this.target, "Getting healed by %N", this.client);
		PrintCenterText(this.client, "Healing %N", this.target);

		if (curTime > this.startTime + this.duration)
		{
			this.Complete();
		}
	}

	bool IsActive()
	{
		return this.startTime != -1.0;
	}
}

HealProgress heal[MAXPLAYERS+1];

public void OnPluginStart()
{
	medkitTime = CreateConVar("sm_team_heal_medkit_time", "8.1");
	bandageTime = CreateConVar("sm_team_heal_bandage_time", "2.8");


	for (int i; i < MaxClients; i++)
		heal[i].Init(i);
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], 
	int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	float curTime = GetGameTime();
	if (nextThink[client] && curTime < nextThink[client])
		return Plugin_Continue;

	nextThink[client] = curTime + 0.1;

	int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
	if (oldButtons & IN_USE && buttons & IN_USE)
	{
		// Client is holding something
		int item = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (item != -1)
		{
			// Client is aiming at a teammate
			int target = GetClientAimTarget(client);
			if (target != -1)
			{
				float targetPos[3], selfPos[3];
				GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetPos);
				GetClientAbsOrigin(client, selfPos);

				if (GetVectorDistance(targetPos, selfPos) < 100.0)
				{
					heal[client].Think(target, item);
					return Plugin_Continue;
				}
			}
		}
	}

	int todo = -1;
	heal[client].Think(todo, todo);

	return Plugin_Continue;
}


stock bool IsPlayerHurt(int client)
{
	return GetClientHealth(client) < GetEntProp(client, Prop_Data, "m_iMaxHealth");
}

stock bool IsPlayerBleeding(int client)
{
	return !!GetEntProp(client, Prop_Send, "_bleedingOut");
}

stock void ShowProgressBar(int client, float duration, float prefill = 0.0)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("ProgressBarShow", client));
	bf.WriteFloat(duration);
	bf.WriteFloat(prefill);
	EndMessage();
}

stock void HideProgressBar(int client)
{
	StartMessageOne("ProgressBarHide", client);
	EndMessage();
}

stock void FreezePlayer(int client)
{
	int curFlags = GetEntProp(client, Prop_Send, "m_fFlags");
	SetEntProp(client, Prop_Send, "m_fFlags", curFlags | 128);
}

stock void UnfreezePlayer(int client)
{
	int curFlags = GetEntProp(client, Prop_Send, "m_fFlags");
	SetEntProp(client, Prop_Send, "m_fFlags", curFlags & ~128);
}

void DoVoiceCommand(int client, VoiceCommand voice)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_Start("TEVoiceCommand");
	TE_WriteNum("_playerIndex", client);
	TE_WriteNum("_voiceCommand", _:voice);
	TE_SendToAllInRange(origin, RangeType_Audibility);
}

void ApplyBandage(int client)
{
	static ConVar hBandageHealAmt;
	if (!hBandageHealAmt)
		hBandageHealAmt = FindConVar("sv_bandage_heal_amt");

	if (GetEntProp(client, Prop_Send, "_bleedingOut"))
		SetEntProp(client, Prop_Send, "_bleedingOut", 0);

	int newHealth = GetClientHealth(client) + hBandageHealAmt.IntValue;
	int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	if (newHealth > maxHealth)
		newHealth = maxHealth;

	SetEntityHealth(client, newHealth);
}

void ApplyFirstAidKit(int client)
{
	static ConVar hFirstAidHealAmt;
	if (!hFirstAidHealAmt)
		hFirstAidHealAmt = FindConVar("sv_first_aid_heal_amt");

	if (GetEntProp(client, Prop_Send, "_bleedingOut"))
		SetEntProp(client, Prop_Send, "_bleedingOut", 0);

	int newHealth = GetClientHealth(client) + hFirstAidHealAmt.IntValue;
	int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	if (newHealth > maxHealth)
		newHealth = maxHealth;

	SetEntityHealth(client, newHealth);
}