from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / 'Sources' / 'Runtime'


class NativeGameplaySystemsTests(unittest.TestCase):
    def _text(self, name: str) -> str:
        path = RUNTIME / name
        self.assertTrue(path.is_file(), f'missing runtime source: {name}')
        return path.read_text(encoding='utf-8')

    def test_model_and_animation_runtime_are_data_driven(self):
        model = self._text('ModelRuntime.swift')
        anim = self._text('AnimationRuntime.swift')
        self.assertIn('struct RuntimeModel', model)
        self.assertIn('boneWeights', model)
        self.assertIn('materialIDs', model)
        self.assertIn('final class AnimationPlayer', anim)
        self.assertIn('notifies', anim)
        self.assertIn('frameRate', anim)

    def test_weapon_and_combat_runtime_have_real_state_machines(self):
        text = self._text('WeaponCombatRuntime.swift')
        for token in ('WeaponDefinition', 'fireIntervalMs', 'reloadTimeMs', 'beginReload', 'applyDamage', 'raycast'):
            self.assertIn(token, text)

    def test_entity_script_runtime_supports_triggers_timers_and_objectives(self):
        text = self._text('EntityScriptRuntime.swift')
        for token in ('RuntimeEntity', 'TriggerVolume', 'scheduleTimer', 'triggerEnter', 'objectiveState', 'setVariable'):
            self.assertIn(token, text)

    def test_zombies_and_multiplayer_are_runtime_modes_not_placeholders(self):
        text = self._text('GameModeRuntime.swift')
        for token in ('ZombieDirector', 'ZombieAgent', 'round', 'points', 'MultiplayerRules', 'respawn', 'score'):
            self.assertIn(token, text)

    def test_game_coordinator_wires_all_native_systems(self):
        text = self._text('BO2GameCoordinator.swift')
        for token in ('QuakeRuntimeController', 'BO2AudioEngine', 'AnimationPlayer', 'WeaponCombatRuntime', 'EntityScriptRuntime', 'GameModeRuntime'):
            self.assertIn(token, text)


if __name__ == '__main__':
    unittest.main()
