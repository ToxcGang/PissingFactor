using UnrealBuildTool;

public class AbioticFactorEditorTarget : TargetRules
{
    public AbioticFactorEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_4;
        WindowsPlatform.CompilerVersion = "14.38.33130";
    }
}
