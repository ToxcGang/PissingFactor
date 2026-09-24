#include "PFBuildCommandlet.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "AssetToolsModule.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Components/SceneComponent.h"
#include "Components/SplineMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "MeshDescription.h"
#include "StaticMeshAttributes.h"
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
#include "K2Node_CallFunction.h"
#include "K2Node_VariableGet.h"
#include "Kismet/KismetMathLibrary.h"
#include "K2Node_Event.h"
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
#include "Materials/MaterialExpressionMultiply.h"
#include "Materials/MaterialExpressionTime.h"
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
    Variable(BP, TEXT("PFPresentationRevision"), Int, TEXT("4"), true);
    Variable(BP, TEXT("PFHasPath"), Bool, TEXT("false"), true);
    Variable(BP, TEXT("PFDuration"), Real, TEXT("0"), true);
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
    Variable(BP, TEXT("PFInputRevision"), Type(UEdGraphSchema_K2::PC_Int), TEXT("3"), false);
    struct Binding { FName Name; FKey Key; };
    const TArray<Binding> Bindings = {
        {TEXT("PFKeyboard"), EKeys::P},
        {TEXT("PFLeft"), EKeys::Gamepad_DPad_Left}
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
    // Inspect compiled bindings as well as graph nodes: only P/Left may consume
    // input. Inventory cycling, dropping and menu actions stay with the game.
    int32 EventCount = 0;
    for (UDynamicBlueprintBinding* Dynamic : CastChecked<UBlueprintGeneratedClass>(BP->GeneratedClass)->DynamicBindingObjects)
    {
        if (const UInputKeyDelegateBinding* Keys = Cast<UInputKeyDelegateBinding>(Dynamic))
        {
            for (const FBlueprintInputKeyDelegateBinding& Entry : Keys->InputKeyDelegateBindings)
            {
                check(Entry.InputChord.Key == EKeys::P || Entry.InputChord.Key == EKeys::Gamepad_DPad_Left);
                check(Entry.bConsumeInput && !Entry.bExecuteWhenPaused);
                check(Entry.InputKeyEvent == IE_Pressed || Entry.InputKeyEvent == IE_Released);
                ++EventCount;
            }
        }
    }
    check(EventCount == 4);
    UE_LOG(LogTemp, Display, TEXT("PissingFactor: input revision 3 verified: P and D-pad Left only, four key events"));
    AActor* CDO = CastChecked<AActor>(BP->GeneratedClass->GetDefaultObject());
    CDO->InputPriority = 100;
    CDO->bBlockInput = false; // only consumed keys; walking and aiming still work
    Save(BP);
}

static void DriverActor()
{
    UBlueprint* BP = Actor(TEXT("ModActor"), false);
    Variable(BP, TEXT("PFHeartbeatSeen"), Type(UEdGraphSchema_K2::PC_Boolean), TEXT("false"), false);
    Variable(BP, TEXT("PFPrototypeRevision"), Type(UEdGraphSchema_K2::PC_Int), TEXT("4"), false);
    FGraphNodeCreator<UK2Node_Event> Creator(*BP->UbergraphPages[0]);
    UK2Node_Event* Tick = Creator.CreateNode();
    Tick->EventReference.SetExternalMember(TEXT("ReceiveTick"), AActor::StaticClass());
    Tick->bOverrideFunction = true;
    Creator.Finalize();
    SetConstant(BP, TEXT("PFHeartbeatSeen"), Tick->FindPinChecked(UEdGraphSchema_K2::PN_Then), TEXT("true"));
    FKismetEditorUtilities::CompileBlueprint(BP);
    check(BP->Status != BS_Error);
    check(BP->GeneratedClass->FindFunctionByName(TEXT("ReceiveTick"))->GetOuter() == BP->GeneratedClass);
    AActor* CDO = CastChecked<AActor>(BP->GeneratedClass->GetDefaultObject());
    CDO->PrimaryActorTick.bCanEverTick = true;
    CDO->PrimaryActorTick.bStartWithTickEnabled = true;
    CDO->PrimaryActorTick.bAllowTickOnDedicatedServer = true;
    CDO->PrimaryActorTick.bTickEvenWhenPaused = true;
    // A nonzero engine tick interval can stop advancing while paused. Lua
    // throttles simulation with real world time and reads diagnostic key edges.
    CDO->PrimaryActorTick.TickInterval = 0.f;
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
    Variable(BP, TEXT("PFLocalNormal"), Vector, TEXT("0,0,1"), true);
    Variable(BP, TEXT("PFAttached"), Type(UEdGraphSchema_K2::PC_Boolean), TEXT("false"), true);
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

static UMaterial* Material(const TCHAR* Name, bool Decal, const FString& Mask)
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
    auto* Time = Expression<UMaterialExpressionTime>(M);
    FCustomInput T; T.InputName=TEXT("Time"); T.Input.Connect(0,Time); Shape->Inputs.Add(T);
    M->GetEditorOnlyData()->BaseColor.Connect(0,Color);
    if (Decal)
    {
        // This expression's class is reflected but not DLL-exported in the
        // installed 5.4 editor. Create it through the registered engine class.
        UClass* LifetimeClass = FindObject<UClass>(nullptr,TEXT("/Script/Engine.MaterialExpressionDecalLifetimeOpacity"));
        check(LifetimeClass);
        auto* Lifetime = NewObject<UMaterialExpression>(M,LifetimeClass);
        M->GetExpressionCollection().AddExpression(Lifetime);
        auto* Fade = Expression<UMaterialExpressionMultiply>(M);
        Fade->A.Connect(0,Shape); Fade->B.Connect(0,Lifetime);
        M->GetEditorOnlyData()->Opacity.Connect(0,Fade);
    }
    else
    {
        M->GetEditorOnlyData()->EmissiveColor.Connect(0,Color);
        M->GetEditorOnlyData()->Opacity.Connect(0,Shape);
    }
    if (FString(Name) == TEXT("M_Stream"))
    {
        bool NeedsRecompile = false;
        M->SetMaterialUsage(NeedsRecompile, MATUSAGE_SplineMesh);
    }
    M->PostEditChange();
    Save(M);
    return M;
}

// Original geometry: a small tube with enough longitudinal subdivisions for
// the spline shader to follow the entire arc. No engine/game meshes are copied.
static UStaticMesh* StreamMesh(UMaterial* StreamMaterial)
{
    UPackage* Package = CreatePackage(*(Root + TEXT("SM_PFStream")));
    UStaticMesh* Mesh = NewObject<UStaticMesh>(Package, TEXT("SM_PFStream"), RF_Public | RF_Standalone);
    FMeshDescription Description;
    FStaticMeshAttributes Attributes(Description);
    Attributes.Register();
    auto Positions = Attributes.GetVertexPositions();
    auto Normals = Attributes.GetVertexInstanceNormals();
    auto Tangents = Attributes.GetVertexInstanceTangents();
    auto Signs = Attributes.GetVertexInstanceBinormalSigns();
    auto UVs = Attributes.GetVertexInstanceUVs();
    UVs.SetNumChannels(1);
    const FPolygonGroupID Group = Description.CreatePolygonGroup();
    Attributes.GetPolygonGroupMaterialSlotNames()[Group] = TEXT("Stream");
    Mesh->GetStaticMaterials().Add(FStaticMaterial(StreamMaterial, TEXT("Stream"), TEXT("Stream")));
    constexpr int32 Rings = 32, Sides = 8;
    FVertexID Vertices[Rings+1][Sides+1];
    for (int32 R=0; R<=Rings; ++R)
    {
        for (int32 S=0; S<=Sides; ++S)
        {
            Vertices[R][S] = Description.CreateVertex();
            const float Angle = 2.f * PI * S / Sides;
            Positions[Vertices[R][S]] = FVector3f(float(R)/Rings, 0.45f*FMath::Cos(Angle), 0.45f*FMath::Sin(Angle));
        }
    }
    auto Instance = [&](int32 R, int32 S)
    {
        FVertexInstanceID I = Description.CreateVertexInstance(Vertices[R][S]);
        const float Angle = 2.f * PI * S / Sides;
        Normals[I] = FVector3f(0,FMath::Cos(Angle),FMath::Sin(Angle));
        Tangents[I] = FVector3f(1,0,0); Signs[I] = 1.f;
        UVs.Set(I,0,FVector2f(float(R)/Rings,float(S)/Sides));
        return I;
    };
    for (int32 R=0; R<Rings; ++R)
    {
        for (int32 S=0; S<Sides; ++S)
        {
            const FVertexInstanceID A[] = {Instance(R,S),Instance(R+1,S),Instance(R+1,S+1)};
            const FVertexInstanceID B[] = {Instance(R,S),Instance(R+1,S+1),Instance(R,S+1)};
            Description.CreateTriangle(Group,MakeArrayView(A));
            Description.CreateTriangle(Group,MakeArrayView(B));
        }
    }
    UStaticMesh::FBuildMeshDescriptionsParams Params;
    Params.bBuildSimpleCollision = false;
    check(Mesh->BuildFromMeshDescriptions({&Description}, Params));
    Save(Mesh);
    return Mesh;
}

static void Link(UEdGraphPin* From, UEdGraphPin* To)
{
    check(GetDefault<UEdGraphSchema_K2>()->TryCreateConnection(From,To));
}

static UK2Node_CallFunction* Call(UBlueprint* BP, UClass* Owner, const TCHAR* Name)
{
    UFunction* Function = Owner->FindFunctionByName(Name);
    check(Function);
    FGraphNodeCreator<UK2Node_CallFunction> Creator(*BP->UbergraphPages[0]);
    auto* Node = Creator.CreateNode();
    Node->SetFromFunction(Function);
    Creator.Finalize();
    return Node;
}

static UEdGraphPin* Get(UBlueprint* BP, FName Name)
{
    FGraphNodeCreator<UK2Node_VariableGet> Creator(*BP->UbergraphPages[0]);
    auto* Node = Creator.CreateNode();
    Node->VariableReference.SetSelfMember(Name);
    Creator.Finalize();
    return Node->GetValuePin();
}

static void Default(UK2Node_CallFunction* Node, const TCHAR* Pin, const TCHAR* Value)
{
    GetDefault<UEdGraphSchema_K2>()->TrySetDefaultValue(*Node->FindPinChecked(Pin),Value);
}

static void StreamActor(UStaticMesh* Mesh)
{
    UBlueprint* BP = Actor(TEXT("BP_PFStream"), false);
    const auto Vector = Type(UEdGraphSchema_K2::PC_Struct,TBaseStructure<FVector>::Get());
    Variable(BP,TEXT("PFUp"),Vector,TEXT("0,0,1"),false);
    for (const FString Suffix : {TEXT("Start"),TEXT("End"),TEXT("TangentA"),TEXT("TangentB")})
    {
        Variable(BP,FName(*(TEXT("PFTarget")+Suffix)),Vector,TEXT("0,0,0"),false);
        Variable(BP,FName(*(TEXT("PFDisplay")+Suffix)),Vector,TEXT("0,0,0"),false);
    }
    USCS_Node* Node = BP->SimpleConstructionScript->CreateNode(USplineMeshComponent::StaticClass(),TEXT("PFStreamMesh"));
    BP->SimpleConstructionScript->GetRootNodes()[0]->AddChildNode(Node);
    auto* Spline = CastChecked<USplineMeshComponent>(Node->ComponentTemplate);
    Spline->SetMobility(EComponentMobility::Movable);
    Spline->SetStaticMesh(Mesh);
    Spline->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    Spline->SetGenerateOverlapEvents(false);
    Spline->SetCanEverAffectNavigation(false);
    Spline->SetCastShadow(false);
    Spline->bReceivesDecals = false;
    Spline->SetForwardAxis(ESplineMeshAxis::X,false);
    Spline->SetBoundaryMin(0,false); Spline->SetBoundaryMax(1,false);
    FKismetEditorUtilities::CompileBlueprint(BP);

    FGraphNodeCreator<UK2Node_Event> Creator(*BP->UbergraphPages[0]);
    auto* Tick = Creator.CreateNode();
    Tick->EventReference.SetExternalMember(TEXT("ReceiveTick"),AActor::StaticClass());
    Tick->bOverrideFunction = true;
    Creator.Finalize();
    UEdGraphPin* Exec = Tick->FindPinChecked(UEdGraphSchema_K2::PN_Then);
    for (const FString Suffix : {TEXT("Start"),TEXT("End"),TEXT("TangentA"),TEXT("TangentB")})
    {
        auto* Interp = Call(BP,UKismetMathLibrary::StaticClass(),TEXT("VInterpTo"));
        Link(Get(BP,FName(*(TEXT("PFDisplay")+Suffix))),Interp->FindPinChecked(TEXT("Current")));
        Link(Get(BP,FName(*(TEXT("PFTarget")+Suffix))),Interp->FindPinChecked(TEXT("Target")));
        Link(Tick->FindPinChecked(TEXT("DeltaSeconds")),Interp->FindPinChecked(TEXT("DeltaTime")));
        Default(Interp,TEXT("InterpSpeed"),TEXT("20"));
        SetFromPin(BP,FName(*(TEXT("PFDisplay")+Suffix)),Interp->GetReturnValuePin(),Exec);
    }
    auto* Move = Call(BP,AActor::StaticClass(),TEXT("K2_SetActorLocation"));
    Link(Exec,Move->GetExecPin()); Exec=Move->GetThenPin();
    Link(Get(BP,TEXT("PFDisplayStart")),Move->FindPinChecked(TEXT("NewLocation")));
    Default(Move,TEXT("bSweep"),TEXT("false")); Default(Move,TEXT("bTeleport"),TEXT("true"));
    auto* Difference = Call(BP,UKismetMathLibrary::StaticClass(),TEXT("Subtract_VectorVector"));
    Link(Get(BP,TEXT("PFDisplayEnd")),Difference->FindPinChecked(TEXT("A")));
    Link(Get(BP,TEXT("PFDisplayStart")),Difference->FindPinChecked(TEXT("B")));
    auto* Update = Call(BP,USplineMeshComponent::StaticClass(),TEXT("SetStartAndEnd"));
    auto* Up = Call(BP,USplineMeshComponent::StaticClass(),TEXT("SetSplineUpDir"));
    Link(Exec,Up->GetExecPin()); Exec=Up->GetThenPin();
    Link(Get(BP,TEXT("PFStreamMesh")),Up->FindPinChecked(UEdGraphSchema_K2::PN_Self));
    Link(Get(BP,TEXT("PFUp")),Up->FindPinChecked(TEXT("InSplineUpDir")));
    Default(Up,TEXT("bUpdateMesh"),TEXT("false"));
    Link(Exec,Update->GetExecPin());
    Link(Get(BP,TEXT("PFStreamMesh")),Update->FindPinChecked(UEdGraphSchema_K2::PN_Self));
    Default(Update,TEXT("StartPos"),TEXT("0,0,0"));
    Link(Difference->GetReturnValuePin(),Update->FindPinChecked(TEXT("EndPos")));
    Link(Get(BP,TEXT("PFDisplayTangentA")),Update->FindPinChecked(TEXT("StartTangent")));
    Link(Get(BP,TEXT("PFDisplayTangentB")),Update->FindPinChecked(TEXT("EndTangent")));
    Default(Update,TEXT("bUpdateMesh"),TEXT("true"));
    FKismetEditorUtilities::CompileBlueprint(BP);
    check(BP->Status != BS_Error);
    auto* CDO = CastChecked<AActor>(BP->GeneratedClass->GetDefaultObject());
    CDO->PrimaryActorTick.bCanEverTick = true;
    CDO->PrimaryActorTick.bStartWithTickEnabled = true;
    CDO->PrimaryActorTick.bAllowTickOnDedicatedServer = false;
    CDO->SetActorHiddenInGame(true);
    check(!CDO->GetIsReplicated());
    Save(BP);
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
    PF::DriverActor();
    UMaterial* StreamMaterial = PF::Material(TEXT("M_Stream"), false,
        TEXT("return Alpha*(0.72+0.28*sin(UV.x*80-Time*25));"));
    PF::StreamActor(PF::StreamMesh(StreamMaterial));
    PF::Material(TEXT("M_Stain"), true,
        TEXT("float2 p=UV*2-1; float r=length(p); float a=atan2(p.y,p.x); return Alpha*(1-smoothstep(0.65+0.08*sin(a*7),0.95,r));"));
    PF::Material(TEXT("M_Cloud"), false,
        TEXT("float r=length(UV*2-1); return Alpha*0.18*(1-smoothstep(0.1,1.0,r));"));
    PF::Material(TEXT("M_Ripple"), false,
        TEXT("float r=length(UV*2-1); return Alpha*(1-smoothstep(0.015,0.07,abs(r-0.75)));"));
    UE_LOG(LogTemp, Display, TEXT("PissingFactor network actor and material generation complete."));
    return 0;
}
