using UnrealBuildTool;

public class PissingFactorEditor : ModuleRules
{
    public PissingFactorEditor(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine", "UnrealEd" });
        PrivateDependencyModuleNames.AddRange(new[] {
            "AssetRegistry", "AssetTools", "BlueprintGraph", "Kismet", "KismetCompiler",
            "UMG", "UMGEditor", "Slate", "SlateCore", "InputCore", "Json", "JsonUtilities",
            "AnimationDataController", "DeveloperSettings", "MeshDescription", "StaticMeshDescription"
        });
    }
}
