"""Check exactly the integration-owned functions; obsolete source is not a deployment."""
import re
import tomllib
from pathlib import Path


def entrypoints(root):
    config = tomllib.loads((root / 'supabase/config.toml').read_text())
    functions = config['functions']
    if not functions:
        raise ValueError('missing_function_inventory')
    entries = []
    for name, settings in sorted(functions.items()):
        if not re.fullmatch('[a-z0-9-]+', name) or settings.get('enabled', True) is not True:
            raise ValueError('invalid_function_inventory')
        path = root / 'supabase/functions' / name / 'index.ts'
        if not path.is_file() or 'entrypoint' in settings:
            raise ValueError('unsupported_function_entrypoint')
        entries.append(path.as_posix())
    return entries


if __name__ == '__main__':
    print('\n'.join(entrypoints(Path('.'))))
