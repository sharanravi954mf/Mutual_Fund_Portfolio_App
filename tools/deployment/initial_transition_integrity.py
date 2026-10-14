"""Permanent initial acceptance gate; no deployment or approval-authority operations."""
import math
import re
from pathlib import Path

import compose_inventory as inventory
from contract import Rejected, manifest, require, revision, target
from owner_common import envelope
from protected_io import read_private
from service_manifest import service_manifest

ARTIFACTS = ('initial-transition.json', 'initial-plan.json', 'initial-verification.json',
             'initial-service-receipt.json', 'initial-failure.json')


def required(config):
    state = Path(config['state_root'])
    initial = config.get('initial_transition', {})
    return initial.get('enabled') is True or initial.get('acceptance_required') is True or any(
        (state / name).exists() or (state / name).is_symlink() for name in ARTIFACTS)


def completed(config, policy, repo, component_manifest=None):
    """Reject partial/old VERIFIED states and every missing or mismatched retained artifact.

    The regular owner's live report and generated override evolve on each reconciliation.
    Initial acceptance therefore binds the permanent private receipt and archived plan.
    """
    try:
        state = Path(config['state_root'])
        journal = read_private(state / 'initial-transition.json')
        require(journal.get('state') == 'VERIFIED', 'initial_transition_not_verified')
        plan = read_private(state / 'initial-plan.json')
        verification = read_private(state / 'initial-verification.json')
        receipt = read_private(state / 'initial-service-receipt.json')
        sha = revision(plan['git_commit'])
        proof = read_private(state / (sha + '.provenance.json'))
        initial = config['initial_transition']
        expected = (manifest if component_manifest is None else component_manifest)(repo, sha)['ingestion_support']
        identity = envelope('dev', target('dev', policy), sha)
        valid = (journal.get('completion_version') == 1 and journal.get('activation_attempted') is True
                 and journal['plan_digest'] == inventory.digest(plan) == verification['plan_digest']
                 and journal['verification_digest'] == inventory.digest(verification)
                 and journal['provenance_digest'] == inventory.digest(proof)
                 and journal['receipt_digest'] == inventory.digest(receipt) == verification['receipt_digest']
                 and verification['receipt'] == receipt and verification['remote'] == plan['remote']
                 and proof == plan['proof'] == dict(image=initial['image'], image_id=initial['candidate_image_id'],
                     git_commit=initial['source_revision'], source_digest=initial['source_digest'])
                 and proof['git_commit'] == sha and proof['source_digest'] == expected
                 and proof['image'].startswith(config['image_repository'] + '@sha256:')
                 and re.fullmatch(r'sha256:[0-9a-f]{64}', proof['image_id'])
                 and all(plan.get(key) == value for key, value in identity.items())
                 and plan['after']['override'] == service_manifest('dev', sha, proof['image'], policy))
        stamp = receipt.get('observed_at')
        valid = valid and type(stamp) in (int, float) and math.isfinite(stamp) and stamp >= 0
        expected_receipt = {**identity, 'observed_at': stamp, 'oracle_dispatcher': 'retired',
                            'component': {'state': 'deployed', 'proof': 'running_image', 'healthy': True,
                                          'source_digest': expected},
                            'image': proof['image'], 'image_id': proof['image_id']}
        after = verification['after']
        api = after['api']
        valid = (valid and receipt == expected_receipt and api['image'] == proof['image_id']
                 and api['id'] != plan['before']['api']['id']
                 and api['labels']['org.opencontainers.image.revision'] == sha
                 and api['labels']['moneybowl.source_digest'] == expected
                 and api['security']['user'] == '10001:10001'
                 and api['state']['Running'] is True and api['state']['Health']['Status'] == 'healthy'
                 and inventory.runtime_identity(api) == plan['after']['runtime_sha256']
                 and after['unrelated'] == plan['before']['unrelated']
                 and after['retired'] == plan['before']['retired'])
        require(valid, 'initial_transition_integrity_failed')
        return receipt
    except Rejected:
        raise
    except (OSError, ValueError, KeyError, TypeError):
        raise Rejected('initial_transition_integrity_failed') from None
