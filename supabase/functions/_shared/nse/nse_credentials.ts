import {
  type MoneyBowlEnvironment,
  NseConfigError,
  type NseEnvironmentReader,
} from "./nse_runtime.ts";

export type NseCredentials = Readonly<{
  loginUserId: string;
  apiKeyMember: string;
  apiSecretUser: string;
  memberCode: string;
}>;

/** Backend-only seam; a future restricted Vault provider can resolve asynchronously. */
export interface NseCredentialProvider {
  readonly kind: "edge-secrets";
  resolve(environment: MoneyBowlEnvironment): Promise<NseCredentials>;
}

const credentialVariables = {
  loginUserId: "NSE_LOGIN_USER_ID",
  apiKeyMember: "NSE_API_KEY_MEMBER",
  apiSecretUser: "NSE_API_SECRET_USER",
  memberCode: "NSE_MEMBER_CODE",
} as const;

export function edgeSecretsProvider(
  read: NseEnvironmentReader,
): NseCredentialProvider {
  return {
    kind: "edge-secrets",
    resolve(_environment) {
      const credentials = {} as Record<keyof NseCredentials, string>;
      const missing: string[] = [];
      for (const [field, variable] of Object.entries(credentialVariables)) {
        const value = read(variable)?.trim();
        if (!value) missing.push(variable);
        else credentials[field as keyof NseCredentials] = value;
      }
      if (missing.length) throw new NseConfigError(missing);
      return Promise.resolve(Object.freeze(credentials));
    },
  };
}

export async function resolveNseCredentials(
  provider: NseCredentialProvider,
  environment: MoneyBowlEnvironment,
): Promise<NseCredentials> {
  try {
    const credentials = await provider.resolve(environment);
    for (
      const field of Object.keys(
        credentialVariables,
      ) as (keyof NseCredentials)[]
    ) {
      if (
        typeof credentials[field] !== "string" || !credentials[field].trim() ||
        /[\x00-\x1f\x7f]/.test(credentials[field])
      ) {
        throw new NseConfigError([credentialVariables[field]]);
      }
    }
    return Object.freeze({
      loginUserId: credentials.loginUserId,
      apiKeyMember: credentials.apiKeyMember,
      apiSecretUser: credentials.apiSecretUser,
      memberCode: credentials.memberCode,
    });
  } catch (error) {
    if (error instanceof NseConfigError) {
      throw new NseConfigError(
        error.missingVariables.filter((name) =>
          (Object.values(credentialVariables) as string[]).includes(name)
        ),
      );
    }
    // Never surface provider errors, causes, HTTP bodies or secret names from Vault.
    throw new NseConfigError();
  }
}
