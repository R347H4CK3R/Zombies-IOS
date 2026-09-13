from __future__ import annotations

from dataclasses import dataclass
import struct

XFILE_HEADER_SIZE = 0x28
XASSET_LIST_SIZE = 0x18
INLINE_POINTER = 0xFFFFFFFF

# Retail console T6 / Black Ops II XAsset IDs. Console builds contain
# PIXELSHADER at 0x07, shifting TECHNIQUE_SET/IMAGE/etc. by one relative to
# some current PC-oriented tool definitions.
XASSET_TYPE_NAMES = (
    'XMODELPIECES', 'PHYSPRESET', 'PHYSCONSTRAINTS', 'DESTRUCTIBLEDEF',
    'XANIMPARTS', 'XMODEL', 'MATERIAL', 'PIXELSHADER', 'TECHNIQUE_SET',
    'IMAGE', 'SOUND', 'SOUND_PATCH', 'CLIPMAP', 'CLIPMAP_PVS', 'COMWORLD',
    'GAMEWORLD_SP', 'GAMEWORLD_MP', 'MAP_ENTS', 'GFXWORLD', 'LIGHT_DEF',
    'UI_MAP', 'FONT', 'FONTICON', 'MENULIST', 'MENU', 'LOCALIZE_ENTRY',
    'WEAPON', 'WEAPONDEF', 'WEAPON_VARIANT', 'WEAPON_FULL', 'ATTACHMENT',
    'ATTACHMENT_UNIQUE', 'WEAPON_CAMO', 'SNDDRIVER_GLOBALS', 'FX',
    'IMPACT_FX', 'AITYPE', 'MPTYPE', 'MPBODY', 'MPHEAD', 'CHARACTER',
    'XMODELALIAS', 'RAWFILE', 'STRINGTABLE', 'LEADERBOARD', 'XGLOBALS', 'DDL',
    'GLASSES', 'TEXTURELIST', 'EMBLEMSET', 'SCRIPTPARSETREE', 'KEYVALUEPAIRS',
    'VEHICLEDEF', 'MEMORYBLOCK', 'ADDON_MAP_ENTS', 'TRACER', 'SKINNEDVERTS',
    'QDB', 'SLUG', 'FOOTSTEP_TABLE', 'FOOTSTEPFX_TABLE', 'ZBARRIER',
)


@dataclass(frozen=True)
class XAssetRecord:
    index: int
    type_id: int
    type_name: str
    header_word: int


@dataclass(frozen=True)
class XAssetListIndex:
    script_strings: tuple[str | None, ...]
    dependencies: tuple[str | None, ...]
    assets: tuple[XAssetRecord, ...]
    script_string_array_offset: int | None
    script_string_data_offset: int | None
    dependency_array_offset: int | None
    asset_array_offset: int | None
    asset_payload_offset: int | None


def _align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def _read_c_string(data: bytes, offset: int) -> tuple[str, int]:
    if offset < 0 or offset >= len(data):
        raise ValueError('inline string starts outside zone')
    end = data.find(b'\0', offset)
    if end < 0:
        raise ValueError('unterminated inline string')
    try:
        value = data[offset:end].decode('utf-8')
    except UnicodeDecodeError:
        value = data[offset:end].decode('latin-1')
    return value, end + 1


def _validate_count(name: str, count: int, maximum: int) -> None:
    if count < 0 or count > maximum:
        raise ValueError(f'invalid {name} count {count}')


def parse_xasset_list(data: bytes, endian: str = '>') -> XAssetListIndex:
    if endian not in ('>', '<'):
        raise ValueError('endian must be > or <')
    if len(data) < XFILE_HEADER_SIZE + XASSET_LIST_SIZE:
        raise ValueError('zone is too small for XFile header and XAssetList')

    # T6 XAssetList on 32-bit targets:
    # ScriptStringList { int count; char **strings; }
    # int dependCount; char **depends; int assetCount; XAsset *assets;
    string_count, string_pointer, depend_count, depend_pointer, asset_count, asset_pointer = struct.unpack_from(
        endian + 'iIiIiI', data, XFILE_HEADER_SIZE
    )
    _validate_count('script-string', string_count, 2_000_000)
    _validate_count('dependency', depend_count, 100_000)
    _validate_count('asset', asset_count, 5_000_000)

    cursor = XFILE_HEADER_SIZE + XASSET_LIST_SIZE
    script_array_offset: int | None = None
    script_data_offset: int | None = None
    dependency_array_offset: int | None = None
    asset_array_offset: int | None = None

    script_strings: list[str | None] = []
    if string_count:
        if string_pointer != INLINE_POINTER:
            raise ValueError(f'external script-string pointer 0x{string_pointer:08X} is unsupported in serialized zone')
        cursor = _align(cursor, 4)
        script_array_offset = cursor
        table_bytes = string_count * 4
        if cursor + table_bytes > len(data):
            raise ValueError('script-string pointer table exceeds zone')
        pointers = struct.unpack_from(endian + f'{string_count}I', data, cursor)
        cursor += table_bytes
        script_data_offset = cursor
        for pointer in pointers:
            if pointer == 0:
                script_strings.append(None)
            elif pointer == INLINE_POINTER:
                value, cursor = _read_c_string(data, cursor)
                script_strings.append(value)
            else:
                raise ValueError(f'external script-string value pointer 0x{pointer:08X} is unsupported')
    elif string_pointer not in (0, INLINE_POINTER):
        raise ValueError(f'unexpected script-string pointer 0x{string_pointer:08X} for empty list')

    dependencies: list[str | None] = []
    if depend_count:
        if depend_pointer != INLINE_POINTER:
            raise ValueError(f'external dependency pointer 0x{depend_pointer:08X} is unsupported in serialized zone')
        cursor = _align(cursor, 4)
        dependency_array_offset = cursor
        table_bytes = depend_count * 4
        if cursor + table_bytes > len(data):
            raise ValueError('dependency pointer table exceeds zone')
        pointers = struct.unpack_from(endian + f'{depend_count}I', data, cursor)
        cursor += table_bytes
        for pointer in pointers:
            if pointer == 0:
                dependencies.append(None)
            elif pointer == INLINE_POINTER:
                value, cursor = _read_c_string(data, cursor)
                dependencies.append(value)
            else:
                raise ValueError(f'external dependency value pointer 0x{pointer:08X} is unsupported')
    elif depend_pointer not in (0, INLINE_POINTER):
        raise ValueError(f'unexpected dependency pointer 0x{depend_pointer:08X} for empty list')

    assets: list[XAssetRecord] = []
    if asset_count:
        if asset_pointer != INLINE_POINTER:
            raise ValueError(f'external asset pointer 0x{asset_pointer:08X} is unsupported in serialized zone')
        cursor = _align(cursor, 4)
        asset_array_offset = cursor
        table_bytes = asset_count * 8
        if cursor + table_bytes > len(data):
            raise ValueError('XAsset table exceeds zone')
        for index in range(asset_count):
            type_id, header_word = struct.unpack_from(endian + 'II', data, cursor + index * 8)
            if not 0 <= type_id < len(XASSET_TYPE_NAMES):
                raise ValueError(f'XAsset {index} has invalid type id {type_id}')
            assets.append(XAssetRecord(index, type_id, XASSET_TYPE_NAMES[type_id], header_word))
        cursor += table_bytes
    elif asset_pointer not in (0, INLINE_POINTER):
        raise ValueError(f'unexpected asset pointer 0x{asset_pointer:08X} for empty list')

    return XAssetListIndex(
        script_strings=tuple(script_strings),
        dependencies=tuple(dependencies),
        assets=tuple(assets),
        script_string_array_offset=script_array_offset,
        script_string_data_offset=script_data_offset,
        dependency_array_offset=dependency_array_offset,
        asset_array_offset=asset_array_offset,
        asset_payload_offset=cursor if asset_count else None,
    )
