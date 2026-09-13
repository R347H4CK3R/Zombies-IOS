#include "GfxWorldResolvedDumperT6.h"

#include <cstdint>
#include <format>
#include <ostream>
#include <string>

using namespace T6;

namespace
{
    std::string BasePath(const XAssetInfo<AssetGfxWorld::Type>& asset)
    {
        return std::format("bo2ios_world/{}/", asset.m_name);
    }

    template<typename T> void WriteRaw(std::ostream& stream, const T* data, const size_t count)
    {
        if (!data || count == 0)
            return;
        stream.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(sizeof(T) * count));
    }
}

namespace bo2_ios::gfx_world
{
    void ResolvedDumperT6::DumpAsset(AssetDumpingContext& context, const XAssetInfo<AssetGfxWorld::Type>& asset)
    {
        const auto* world = asset.Asset();
        if (!world)
            return;

        const auto base = BasePath(asset);

        if (const auto metaFile = context.OpenAssetFile(base + "meta.tsv"))
        {
            auto& out = *metaFile;
            out << "format\tbo2ios-resolved-gfxworld-v1\n";
            out << "name\t" << (world->name ? world->name : "") << "\n";
            out << "baseName\t" << (world->baseName ? world->baseName : "") << "\n";
            out << "planeCount\t" << world->planeCount << "\n";
            out << "nodeCount\t" << world->nodeCount << "\n";
            out << "surfaceCount\t" << world->surfaceCount << "\n";
            out << "vertexCount\t" << world->draw.vertexCount << "\n";
            out << "vertexDataSize0\t" << world->draw.vertexDataSize0 << "\n";
            out << "vertexDataSize1\t" << world->draw.vertexDataSize1 << "\n";
            out << "indexCount\t" << world->draw.indexCount << "\n";
            out << "reflectionProbeCount\t" << world->draw.reflectionProbeCount << "\n";
            out << "lightmapCount\t" << world->draw.lightmapCount << "\n";
            out << "staticSurfaceCount\t" << world->dpvs.staticSurfaceCount << "\n";
            out << "smodelCount\t" << world->dpvs.smodelCount << "\n";
            out << "litSurfsBegin\t" << world->dpvs.litSurfsBegin << "\n";
            out << "litSurfsEnd\t" << world->dpvs.litSurfsEnd << "\n";
            out << "litTransSurfsBegin\t" << world->dpvs.litTransSurfsBegin << "\n";
            out << "litTransSurfsEnd\t" << world->dpvs.litTransSurfsEnd << "\n";
            out << "emissiveOpaqueSurfsBegin\t" << world->dpvs.emissiveOpaqueSurfsBegin << "\n";
            out << "emissiveOpaqueSurfsEnd\t" << world->dpvs.emissiveOpaqueSurfsEnd << "\n";
            out << "emissiveTransSurfsBegin\t" << world->dpvs.emissiveTransSurfsBegin << "\n";
            out << "emissiveTransSurfsEnd\t" << world->dpvs.emissiveTransSurfsEnd << "\n";
        }

        if (const auto file = context.OpenAssetFile(base + "vertex0.bin"))
        {
            if (world->draw.vd0.data && world->draw.vertexDataSize0)
                file->write(reinterpret_cast<const char*>(world->draw.vd0.data), world->draw.vertexDataSize0);
        }
        if (const auto file = context.OpenAssetFile(base + "vertex1.bin"))
        {
            if (world->draw.vd1.data && world->draw.vertexDataSize1)
                file->write(reinterpret_cast<const char*>(world->draw.vd1.data), world->draw.vertexDataSize1);
        }
        if (const auto file = context.OpenAssetFile(base + "indices.u16"))
            WriteRaw(*file, world->draw.indices, static_cast<size_t>(world->draw.indexCount));

        if (const auto surfaceFile = context.OpenAssetFile(base + "surfaces.tsv"))
        {
            auto& out = *surfaceFile;
            out << "index\tvertexDataOffset0\tvertexDataOffset1\tfirstVertex\tvertexCount\ttriCount\tbaseIndex\tmaterial\ttechset\tworldVertFormat\tlightmapIndex\treflectionProbeIndex\tprimaryLightIndex\tflags\tminX\tminY\tminZ\tmaxX\tmaxY\tmaxZ\n";
            for (unsigned int i = 0; i < world->dpvs.staticSurfaceCount; ++i)
            {
                const auto& surface = world->dpvs.surfaces[i];
                const auto* material = surface.material;
                const auto* techset = material ? material->techniqueSet : nullptr;
                const char* materialName = material && material->info.name ? material->info.name : "";
                const char* techsetName = techset && techset->name ? techset->name : "";
                const auto format = techset ? static_cast<int>(techset->worldVertFormat) : -1;
                const auto& tris = surface.tris;
                out << i << '\t'
                    << tris.vertexDataOffset0 << '\t' << tris.vertexDataOffset1 << '\t'
                    << tris.firstVertex << '\t' << tris.vertexCount << '\t' << tris.triCount << '\t' << tris.baseIndex << '\t'
                    << materialName << '\t' << techsetName << '\t' << format << '\t'
                    << static_cast<unsigned int>(static_cast<unsigned char>(surface.lightmapIndex)) << '\t'
                    << static_cast<unsigned int>(static_cast<unsigned char>(surface.reflectionProbeIndex)) << '\t'
                    << static_cast<unsigned int>(static_cast<unsigned char>(surface.primaryLightIndex)) << '\t'
                    << static_cast<unsigned int>(static_cast<unsigned char>(surface.flags)) << '\t'
                    << surface.bounds[0].x << '\t' << surface.bounds[0].y << '\t' << surface.bounds[0].z << '\t'
                    << surface.bounds[1].x << '\t' << surface.bounds[1].y << '\t' << surface.bounds[1].z << '\n';
            }
        }

        if (const auto modelFile = context.OpenAssetFile(base + "static_models.tsv"))
        {
            auto& out = *modelFile;
            out << "index\tmodel\tcullDist\toriginX\toriginY\toriginZ\taxis00\taxis01\taxis02\taxis10\taxis11\taxis12\taxis20\taxis21\taxis22\tscale\tflags\n";
            for (unsigned int i = 0; i < world->dpvs.smodelCount; ++i)
            {
                const auto& inst = world->dpvs.smodelDrawInsts[i];
                const auto* model = inst.model;
                const auto& p = inst.placement;
                out << i << '\t' << (model && model->name ? model->name : "") << '\t' << inst.cullDist << '\t'
                    << p.origin.x << '\t' << p.origin.y << '\t' << p.origin.z << '\t'
                    << p.axis[0].x << '\t' << p.axis[0].y << '\t' << p.axis[0].z << '\t'
                    << p.axis[1].x << '\t' << p.axis[1].y << '\t' << p.axis[1].z << '\t'
                    << p.axis[2].x << '\t' << p.axis[2].y << '\t' << p.axis[2].z << '\t'
                    << p.scale << '\t' << inst.flags << '\n';
            }
        }
    }
}
