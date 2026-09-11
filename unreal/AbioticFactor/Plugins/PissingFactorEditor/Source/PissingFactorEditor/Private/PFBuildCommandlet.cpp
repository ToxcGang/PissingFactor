#include "PFBuildCommandlet.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "AssetToolsModule.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Components/SceneComponent.h"
#include "EdGraph/EdGraph.h"
#include "EdGraphSchema_K2.h"
#include "Engine/Blueprint.h"
#include "Engine/BlueprintGeneratedClass.h"
#include "Engine/InputKeyDelegateBinding.h"
#include "Engine/SimpleConstructionScript.h"
#include "Engine/SCS_Node.h"
#include "Factories/BlueprintFactory.h"
#include "GameFramework/Actor.h"
#include "GameFramework/Pawn.h"
#include "K2Node_CustomEvent.h"
#include "K2Node_InputKey.h"
#include "K2Node_VariableSet.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Materials/Material.h"
#include "MaterialDomain.h"
#include "Materials/MaterialExpressionConstant.h"
#include "Materials/MaterialExpressionConstant3Vector.h"
#include "Materials/MaterialExpressionScalarParameter.h"
#include "Materials/MaterialExpressionTextureCoordinate.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/PackageName.h"
#include "UObject/SavePackage.h"
#include "InputCoreTypes.h"

namespace PF
{
static const FString Root = TEXT("/Game/Mods/PissingFactor/");

static void Save(UObject* Object)
{
    UPackage* Package = Object->GetOutermost();
    // This commandlet reconstructs the entire generated package from source.
    // There are no unloaded exports from a previous generated revision to retain.
    Package->MarkAsFullyLoaded();
    FAssetRegistryModule::AssetCreated(Object);
    Object->MarkPackageDirty();
    const FString Filename = FPackageName::LongPackageNameToFilename(Package->GetName(), FPackageName::GetAssetPackageExtension());
    FSavePackageArgs Args;
    Args.TopLevelFlags = RF_Public | RF_Standalone;
    Args.SaveFlags = SAVE_None;
    if (!UPackage::SavePackage(Package, Object, *Filename, Args))
    {
        UE_LOG(LogTemp, Fatal, TEXT("PissingFactor: cannot save %s"), *Filename);
    }
}

static FEdGraphPinType Type(FName Category, UObject* Subtype = nullptr)
{
    FEdGraphPinType T;
    T.PinCategory = Category;
    T.PinSubCategoryObject = Subtype;
    return T;
}

static void Variable(UBlueprint* BP, FName Name, const FEdGraphPinType& T, const FString& Default, bool Replicated)
{
    if (!FBlueprintEditorUtils::AddMemberVariable(BP, Name, T, Default))
    {
        UE_LOG(LogTemp, Fatal, TEXT("Cannot create variable %s"), *Name.ToString());
    }
    if (Replicated)
    {
        const int32 Index = FBlueprintEditorUtils::FindNewVariableIndex(BP, Name);
        check(Index != INDEX_NONE);
        BP->NewVariables[Index].PropertyFlags |= CPF_Net;
    }
}

static UBlueprint* Actor(const TCHAR* Name, bool Replicated)
{
    UPackage* Package = CreatePackage(*(Root + Name));
    UBlueprint* BP = FKismetEditorUtilities::CreateBlueprint(AActor::StaticClass(), Package,
        FName(Name), BPTYPE_Normal, UBlueprint::StaticClass(), UBlueprintGeneratedClass::StaticClass());
    USCS_Node* Scene = BP->SimpleConstructionScript->CreateNode(USceneComponent::StaticClass(), TEXT("PFRoot"));
    BP->SimpleConstructionScript->AddNode(Scene);
    FKismetEditorUtilities::CompileBlueprint(BP);
    AActor* CDO = CastChecked<AActor>(BP->GeneratedClass->GetDefaultObject());
    FBoolProperty* ReplicationProperty = FindFProperty<FBoolProperty>(AActor::StaticClass(), TEXT("bReplicates"));
    check(ReplicationProperty);
    ReplicationProperty->SetPropertyValue_InContainer(CDO, Replicated);
    CDO->SetReplicateMovement(Replicated);
    CDO->bOnlyRelevantToOwner = false;
    CDO->bNetUseOwnerRelevancy = false;
    CDO->NetUpdateFrequency = 10.f;
    CDO->MinNetUpdateFrequency = 10.f;
    CDO->SetCanBeDamaged(false);
    return BP;
}

static UK2Node_CustomEvent* Event(UBlueprint* BP, const TCHAR* Name, bool Server = false, bool Reliable = true)
{
    UEdGraph* Graph = BP->UbergraphPages[0];
    FGraphNodeCreator<UK2Node_CustomEvent> Creator(*Graph);
    UK2Node_CustomEvent* Node = Creator.CreateNode();
    Node->CustomFunctionName = Name;
    Node->FunctionFlags = FUNC_Public | FUNC_BlueprintCallable | FUNC_BlueprintEvent;
    if (Server) Node->FunctionFlags |= FUNC_Net | FUNC_NetServer;
    if (Server && Reliable) Node->FunctionFlags |= FUNC_NetReliable;
    Creator.Finalize();
    return Node;
}

static void SetFromPin(UBlueprint* BP, FName VariableName, UEdGraphPin* Value, UEdGraphPin*& Exec)
{
    UEdGraph* Graph = BP->UbergraphPages[0];
    FGraphNodeCreator<UK2Node_VariableSet> Creator(*Graph);
    UK2Node_VariableSet* Set = Creator.CreateNode();
    Set->VariableReference.SetSelfMember(VariableName);
    Creator.Finalize();
    const UEdGraphSchema_K2* Schema = GetDefault<UEdGraphSchema_K2>();
    if (!Schema->TryCreateConnection(Exec, Set->GetExecPin()) ||
        !Schema->TryCreateConnection(Value, Set->FindPinChecked(VariableName)))
    {
        UE_LOG(LogTemp, Fatal, TEXT("Could not wire RPC mailbox %s"), *VariableName.ToString());
    }
    Exec = Set->GetThenPin();
}

static void PlayerActor()
{
    UBlueprint* BP = Actor(TEXT("BP_PFPlayer"), true);
    const auto Bool = Type(UEdGraphSchema_K2::PC_Boolean);
    const auto Int = Type(UEdGraphSchema_K2::PC_Int);
    const auto String = Type(UEdGraphSchema_K2::PC_String);
    const auto Vector = Type(UEdGraphSchema_K2::PC_Struct, TBaseStructure<FVector>::Get());
    auto Real = Type(UEdGraphSchema_K2::PC_Real);
    Real.PinSubCategory = UEdGraphSchema_K2::PC_Double;
    Variable(BP, TEXT("PFPawn"), Type(UEdGraphSchema_K2::PC_Object, APawn::StaticClass()), TEXT("None"), true);
    Variable(BP, TEXT("PFActive"), Bool, TEXT("false"), true);
    Variable(BP, TEXT("PFOrigin"), Vector, TEXT("0,0,0"), true);
    Variable(BP, TEXT("PFAim"), Vector, TEXT("1,0,0"), true);
    Variable(BP, TEXT("PFEndpoint"), Vector, TEXT("0,0,0"), true);
    Variable(BP, TEXT("PFServerTime"), Real, TEXT("0"), true);
    Variable(BP, TEXT("PFRange"), Real, TEXT("400"), true);
    Variable(BP, TEXT("PFReason"), String, TEXT("not_connected"), true);
    Variable(BP, TEXT("PFVersion"), String, TEXT("1.0.0"), true);
    Variable(BP, TEXT("PFProtocol"), Int, TEXT("1"), true);
    Variable(BP, TEXT("PFInputSequence"), Int, TEXT("-1"), false);
    Variable(BP, TEXT("PFInputHeld"), Bool, TEXT("false"), false);
    Variable(BP, TEXT("PFInputAim"), Vector, TEXT("1,0,0"), false);
    Variable(BP, TEXT("PFInputVersion"), String, TEXT(""), false);
    Variable(BP, TEXT("PFInputProtocol"), Int, TEXT("0"), false);
    struct Param { FName Name; FName Target; FEdGraphPinType T; };
    const TArray<Param> Params = {
        {TEXT("Sequence"), TEXT("PFInputSequence"), Int},
        {TEXT("Held"), TEXT("PFInputHeld"), Bool},
        {TEXT("Aim"), TEXT("PFInputAim"), Vector},
        {TEXT("ModVersion"), TEXT("PFInputVersion"), String},
        {TEXT("Protocol"), TEXT("PFInputProtocol"), Int}
    };
    for (int32 RPCIndex = 0; RPCIndex < 2; ++RPCIndex)
    {
        UK2Node_CustomEvent* RPC = Event(BP, RPCIndex == 0 ? TEXT("ServerSetInput") : TEXT("ServerUpdateAim"), true, RPCIndex == 0);
        UEdGraphPin* Exec = RPC->FindPinChecked(UEdGraphSchema_K2::PN_Then);
        for (const Param& P : Params)
        {
            UEdGraphPin* Pin = RPC->CreateUserDefinedPin(P.Name, P.T, EGPD_Output);
            SetFromPin(BP, P.Target, Pin, Exec);
        }
    }
    FKismetEditorUtilities::CompileBlueprint(BP);
    check(BP->Status != BS_Error);
    check(CastChecked<AActor>(BP->GeneratedClass->GetDefaultObject())->GetIsReplicated());
    check(BP->GeneratedClass->FindFunctionByName(TEXT("ServerSetInput"))->HasAllFunctionFlags(FUNC_Net | FUNC_NetServer | FUNC_NetReliable));
    check(BP->GeneratedClass->FindFunctionByName(TEXT("ServerUpdateAim"))->HasAllFunctionFlags(FUNC_Net | FUNC_NetServer));
    check(!BP->GeneratedClass->FindFunctionByName(TEXT("ServerUpdateAim"))->HasAnyFunctionFlags(FUNC_NetReliable));
    Save(BP);
}

static void SetConstant(UBlueprint* BP, FName Name, UEdGraphPin* Exec, const FString& Value)
{
    FGraphNodeCreator<UK2Node_VariableSet> Creator(*BP->UbergraphPages[0]);
    UK2Node_VariableSet* Set = Creator.CreateNode();
    Set->VariableReference.SetSelfMember(Name);
    Creator.Finalize();
    const UEdGraphSchema_K2* Schema = GetDefault<UEdGraphSchema_K2>();
    check(Schema->TryCreateConnection(Exec, Set->GetExecPin()));
    Schema->TrySetDefaultValue(*Set->FindPinChecked(Name), Value);
}

static void InputActor()
{
    UBlueprint* BP = Actor(TEXT("BP_PFInput"), false);
    struct Binding { FName Name; FKey Key; };
    const TArray<Binding> Bindings = {
        {TEXT("PFKeyboard"), EKeys::P},
        {TEXT("PFBumper"), EKeys::Gamepad_LeftShoulder},
        {TEXT("PFDown"), EKeys::Gamepad_DPad_Down},
        {TEXT("PFSettings"), EKeys::F8},
        {TEXT("PFMenu"), EKeys::Gamepad_Special_Right}
    };
    for (const Binding& Binding : Bindings)
    {
        Variable(BP, Binding.Name, Type(UEdGraphSchema_K2::PC_Boolean), TEXT("false"), false);
        FGraphNodeCreator<UK2Node_InputKey> Creator(*BP->UbergraphPages[0]);
        UK2Node_InputKey* Key = Creator.CreateNode();
        Key->InputKey = Binding.Key;
        Key->bConsumeInput = true;
        Key->bExecuteWhenPaused = false;
        Creator.Finalize();
        SetConstant(BP, Binding.Name, Key->GetPressedPin(), TEXT("true"));
        SetConstant(BP, Binding.Name, Key->GetReleasedPin(), TEXT("false"));
    }
    FKismetEditorUtilities::CompileBlueprint(BP);
    check(BP->Status != BS_Error);
    AActor* CDO = CastChecked<AActor>(BP->GeneratedClass->GetDefaultObject());
    CDO->InputPriority = 100;
    CDO->bBlockInput = false; // only consumed keys; walking and aiming still work
    Save(BP);
}

static void ImpactActor()
{
    UBlueprint* BP = Actor(TEXT("BP_PFImpact"), true);
    const auto Vector = Type(UEdGraphSchema_K2::PC_Struct, TBaseStructure<FVector>::Get());
    auto Real = Type(UEdGraphSchema_K2::PC_Real); Real.PinSubCategory = UEdGraphSchema_K2::PC_Double;
    Variable(BP, TEXT("PFKind"), Type(UEdGraphSchema_K2::PC_String), TEXT("solid"), true);
    Variable(BP, TEXT("PFNormal"), Vector, TEXT("0,0,1"), true);
    Variable(BP, TEXT("PFExpires"), Real, TEXT("0"), true);
    Variable(BP, TEXT("PFFade"), Real, TEXT("10"), true);
    Variable(BP, TEXT("PFCreated"), Real, TEXT("0"), true);
    Variable(BP, TEXT("PFLocalPosition"), Vector, TEXT("0,0,0"), true);
    Variable(BP, TEXT("PFSurface"), Type(UEdGraphSchema_K2::PC_Object, USceneComponent::StaticClass()), TEXT("None"), true);
    FKismetEditorUtilities::CompileBlueprint(BP);
    check(BP->Status != BS_Error);
    Save(BP);
}

template<class T> static T* Expression(UMaterial* Material)
{
    T* Expr = NewObject<T>(Material);
    Material->GetExpressionCollection().AddExpression(Expr);
    return Expr;
}

static void Material(const TCHAR* Name, bool Decal, const FString& Mask)
{
    UPackage* Package = CreatePackage(*(Root + Name));
    UMaterial* M = NewObject<UMaterial>(Package, Name, RF_Public | RF_Standalone);
    M->MaterialDomain = Decal ? MD_DeferredDecal : MD_Surface;
    M->BlendMode = BLEND_Translucent;
    M->SetShadingModel(Decal ? MSM_DefaultLit : MSM_Unlit);
    M->TwoSided = true;
    auto* Color = Expression<UMaterialExpressionConstant3Vector>(M);
    Color->Constant = FLinearColor(0.8f, 0.52f, 0.012f);
    auto* Opacity = Expression<UMaterialExpressionScalarParameter>(M);
    Opacity->ParameterName = TEXT("Opacity"); Opacity->DefaultValue = 0.7f;
    auto* UV = Expression<UMaterialExpressionTextureCoordinate>(M);
    auto* Shape = Expression<UMaterialExpressionCustom>(M);
    Shape->Code = Mask;
    Shape->OutputType = CMOT_Float1;
    FCustomInput U; U.InputName=TEXT("UV"); U.Input.Connect(0,UV); Shape->Inputs.Add(U);
    FCustomInput O; O.InputName=TEXT("Alpha"); O.Input.Connect(0,Opacity); Shape->Inputs.Add(O);
    M->GetEditorOnlyData()->BaseColor.Connect(0,Color);
    M->GetEditorOnlyData()->EmissiveColor.Connect(0,Color);
    M->GetEditorOnlyData()->Opacity.Connect(0,Shape);
    M->PostEditChange();
    Save(M);
}
}

UPFBuildCommandlet::UPFBuildCommandlet()
{
    IsClient = false; IsServer = false; IsEditor = true; LogToConsole = true;
}

int32 UPFBuildCommandlet::Main(const FString& Params)
{
    PF::PlayerActor();
    PF::ImpactActor();
    PF::InputActor();
    PF::Save(PF::Actor(TEXT("ModActor"), false));
    PF::Material(TEXT("M_Stream"), false, TEXT("return Alpha;"));
    PF::Material(TEXT("M_Stain"), true,
        TEXT("float2 p=UV*2-1; float r=length(p); float a=atan2(p.y,p.x); return Alpha*(1-smoothstep(0.65+0.08*sin(a*7),0.95,r));"));
    PF::Material(TEXT("M_Cloud"), false,
        TEXT("float r=length(UV*2-1); return Alpha*0.18*(1-smoothstep(0.1,1.0,r));"));
    PF::Material(TEXT("M_Ripple"), false,
        TEXT("float r=length(UV*2-1); return Alpha*(1-smoothstep(0.015,0.07,abs(r-0.75)));"));
    UE_LOG(LogTemp, Display, TEXT("PissingFactor network actor and material generation complete."));
    return 0;
}
