#pragma once

#include "Dumping/AbstractAssetDumper.h"
#include "Game/T6/T6.h"

namespace bo2_ios::gfx_world
{
    class ResolvedDumperT6 final : public AbstractAssetDumper<T6::AssetGfxWorld>
    {
    protected:
        void DumpAsset(AssetDumpingContext& context, const XAssetInfo<T6::AssetGfxWorld::Type>& asset) override;
    };
}
