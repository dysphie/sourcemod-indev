#include <sdktools>

#define ASSERT(%1) if (!%1) ThrowError("\""...#%1..."\" is false")

stock Address operator+(Address base, int off) {
	return base + Address:off;
}

methodmap AddressBase {
	property Address addr {
		public get() { 
			return Address:this; 
		}
	}
}

methodmap UtlVector < AddressBase 
{
	public UtlVector(Address addr) {
		return UtlVector:addr;
	}

	property int size {
		public get() {
			return LoadFromAddress(this.addr + 0xC, NumberType_Int32);
		}
	}

	property Address elements {
		public get() {
			return Address:LoadFromAddress(this.addr, NumberType_Int32);
		}
	}

	public any Get(int idx, int elemSize = 0x4) {
		return any:LoadFromAddress(this.elements + idx * elemSize, NumberType_Int32);
	}
}


methodmap ObjectiveBoundary < AddressBase {

	public ObjectiveBoundary(Address addr) {
		return ObjectiveBoundary:addr;
	}

	public void Finish() {
		ObjectiveBoundary_Finish(this.addr);
	}
}

methodmap Objective < AddressBase {

	public Objective(Address addr) {
		return Objective:addr;
	}

	property UtlVector links {
		public get() {
			Address addr = Address:LoadFromAddress(this.addr + 0x20, NumberType_Int32);
			return UtlVector(addr);
		}
	}

	property int id {
		public get() { 
			return LoadFromAddress(this.addr, NumberType_Int32);
		}
	}

	property UtlVector entityList {
		public get() {
			return UtlVector(this.addr + 0xC);
		}
	}

	property int name {
		public get() {
			return LoadFromAddress(this.addr + 0x4, NumberType_Int32);
		}
	}

	property int description {
		public get() {
			return LoadFromAddress(this.addr + 0x8, NumberType_Int32);
		}
	}

	// TODO: return bytes written
	public void GetName(char[] buffer, int maxlen) {
		
		ASSERT(this.name);
		UTIL_StringtToCharArray(Address:this.name, buffer, maxlen);
	}

	// ^
	public void GetDescription(char[] buffer, int maxlen)
	{
		ASSERT(this.name);
		UTIL_StringtToCharArray(Address:this.description, buffer, maxlen);
	}

	public bool IsEndObjective()
	{
		return !this.links.size;
	}
}

methodmap ObjectiveManager < AddressBase {

	public ObjectiveManager(Address addr) {
		return ObjectiveManager:addr;
	}

	property ObjectiveBoundary currentObjectiveBoundary {
		public get() {
			Address addr = Address:LoadFromAddress(this.addr + 0x7C, NumberType_Int32);
			return ObjectiveBoundary(addr);
		}
	}

	property int currentObjectiveIndex {
		public get() {
			return LoadFromAddress(this.addr + 0x70, NumberType_Int32);
		}

		public set(int value) {
			StoreToAddress(this.addr + 0x70, value, NumberType_Int32);
		}
	}

	property Objective currentObjective {
		public get() {
			Address addr = Address:LoadFromAddress(this.addr + 0x78, NumberType_Int32);
			return Objective(addr);
		}
	}

	property UtlVector objectives {
		public get() {
			return UtlVector(this.addr + 0x14);
		}
	}

	property bool completed {
		public get() {
			return !!LoadFromAddress(this.addr + 0x6C, NumberType_Int8);
		}

		public set(bool value) {
			StoreToAddress(this.addr + 0x6C, value, NumberType_Int8);
		}
	}

	public void StartNextObjective() {
		ObjectiveManager_StartNextObjective(this.addr);
	}

	public void CompleteCurrentObjective() {
		ObjectiveBoundary boundary = this.currentObjectiveBoundary;

		if (boundary.addr)
			boundary.Finish();

		Objective objective = this.currentObjective;
		ASSERT(objective);

		if (objective.IsEndObjective())
		{
			this.completed = true;
		}
		else
		{
			this.currentObjectiveIndex++;
			this.StartNextObjective();
		}
	}

	public int GetObjectiveIndex(Objective objective)
	{
		UtlVector objectives = this.objectives;
		ASSERT(objectives);
		
		int len = objectives.size;
		for (int i; i < len; i++)
			if (objectives.Get(i) == objective)
				return i; 
		return -1;
	}

	public Objective GetObjectiveByID(int id)
	{
		return ObjectiveManager_GetObjectiveById(this.addr, id);
	}

}

ObjectiveManager objMgr;

Handle hBoundaryFinish;
Handle hStartNextObjective;
Handle hGetObjectiveByID;

public void OnPluginStart()
{
	GameData gamedata = new GameData("objectives.nmrih");
	if(!gamedata)
		SetFailState("Failed to load gamedata");

	objMgr = ObjectiveManager(gamedata.GetAddress("CNMRiH_ObjectiveManager"));
	if(!objMgr.addr)
		SetFailState("Failed to retrieve the objective manager");

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetSignature(SDKLibrary_Server, "\x55\x8B\xEC\x56\x8B\x71\x20", 7);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hGetObjectiveByID = EndPrepSDKCall();
	ASSERT(hGetObjectiveByID);

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetSignature(SDKLibrary_Server, 
		"\x55\x8B\xEC\x51\x56\x57\x8B\xF9\xC6\x45\xFF\x00\x8D\x4D\xFF\x8A\x87\x8C\x03\x00\x00", 21);
	hBoundaryFinish = EndPrepSDKCall();
	ASSERT(hBoundaryFinish);

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetSignature(SDKLibrary_Server, 
		"\x55\x8B\xEC\x83\xEC\x2C\x53\x56\x57\x8B\xF9\x89\x7D\xF8", 14);
	hStartNextObjective = EndPrepSDKCall();
	ASSERT(hStartNextObjective);

	HookEvent("objective_complete", OnObjectiveComplete, EventHookMode_Pre);
	RegConsoleCmd("sm_test", OnCmdTest);
}

public Action OnCmdTest(int client, int args)
{
	PrintToServer("ObjectiveManager.currentObjectiveIndex -> %d", objMgr.currentObjectiveIndex);

	Objective curObj = objMgr.currentObjective;
	PrintToServer("ObjectiveManager.currentObjective -> %x", curObj);
	PrintToServer("Objective.links -> %x", curObj.links);
	PrintToServer("Objective.id -> %d", curObj.id);
	PrintToServer("Objective.IsEndObjective() -> %d", curObj.IsEndObjective());

	ObjectiveBoundary boundary = objMgr.currentObjectiveBoundary;
	PrintToServer("objMgr.currentObjectiveBoundary -> %x", boundary);

	GetObjectiveEntities();
	objMgr.CompleteCurrentObjective();

	return Plugin_Handled;
}


void GetObjectiveEntities()
{
	UtlVector objectives = objMgr.objectives;
	if (!objectives.addr)
		return;

	char entName[64], objName[64];

	int maxObjs = objectives.size;
	for (int i; i < maxObjs; i++)
	{
		Objective objective = objectives.Get(i);
		ASSERT(objective);

		UtlVector entityList = objective.entityList;
		ASSERT(entityList);
		
		objective.GetName(objName, sizeof(objName));

		int maxEnts = entityList.size;
		for (int e; e < maxEnts; e++)
		{
			Address pEntName = entityList.Get(e);
			ASSERT(pEntName);

			UTIL_StringtToCharArray(pEntName, entName, sizeof(entName));
			PrintToServer("%s -> %s", objName, entName)
		}
	}
}

public void ObjectiveManager_StartNextObjective(Address addr)
{ 
	SDKCall(hStartNextObjective, addr);
}

public void ObjectiveBoundary_Finish(Address addr)
{
	SDKCall(hBoundaryFinish, addr);
}

Objective ObjectiveManager_GetObjectiveById(Address self, int id)
{
	return Objective((SDKCall(hGetObjectiveByID, self, id)));	
}

void UTIL_StringtToCharArray(Address pSrc, char[] dest, int len)
{
	int i;
	while (--len && (dest[i] = LoadFromAddress(pSrc + Address:i, NumberType_Int8)) != 0)
		i++; 
	dest[i] = 0;
}

bool ignoreObjectives;
public Action OnObjectiveComplete(Event event, const char[] name, bool silent)
{
	if (ignoreObjectives)
		return Plugin_Continue;

	Objective pCurObj = objMgr.currentObjective;
	ASSERT(pCurObj);

	int doneObjID = event.GetInt("id");
	Objective pDoneObj = objMgr.GetObjectiveByID(doneObjID);
	ASSERT(pDoneObj);

	int skipped = objMgr.GetObjectiveIndex(pDoneObj) - objMgr.GetObjectiveIndex(pCurObj);
	
	if (skipped > 0) {
		/* Complete intermediate objectives to break the map less */
		ignoreObjectives = true;
		do {
			objMgr.CompleteCurrentObjective();
			skipped--;
		} while (skipped)
		ignoreObjectives = false;
	}

	return Plugin_Continue;
}