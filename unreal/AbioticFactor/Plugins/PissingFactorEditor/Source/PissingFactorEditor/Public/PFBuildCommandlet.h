#pragma once

#include "Commandlets/Commandlet.h"
#include "PFBuildCommandlet.generated.h"

/** Builds mod-owned assets; it never packages imported game assets. */
UCLASS()
class UPFBuildCommandlet : public UCommandlet
{
    GENERATED_BODY()
public:
    UPFBuildCommandlet();
    virtual int32 Main(const FString& Params) override;
};
