"""Generate an immutable ingestion override for its existing private deployment owner."""
import argparse
import json
import re
from pathlib import Path
from contract import load_policy, require, revision, target


def service_manifest(environment, sha, image, policy):
    require(environment in ('dev', 'qa'), 'invalid_environment')
    require(policy[environment]['deployment_enabled'] is True, 'environment_not_commissioned')
    target(environment, policy)
    revision(sha)
    require(isinstance(image, str) and re.fullmatch(
        r'[a-z0-9][a-z0-9./_-]+@sha256:[0-9a-f]{64}', image), 'immutable_image_required')
    return {'services': {'api': {'image': image, 'scale': 1, 'deploy': {'replicas': 1},
            'labels': {'org.opencontainers.image.revision': sha, 'moneybowl.environment': environment}}}}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--environment', required=True)
    p.add_argument('--revision', required=True)
    p.add_argument('--image', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    try:
        result = service_manifest(args.environment, args.revision, args.image, load_policy())
        Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
        print('{"state":"manifest_prepared","deployed":false}')
        return 0
    except Exception:
        print('{"state":"failed","reason":"invalid_service_release"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
