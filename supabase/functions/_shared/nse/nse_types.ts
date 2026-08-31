export type NseConfig = Readonly<{
  baseUrl: string;
  loginUserId: string;
  apiKeyMember: string;
  apiSecretUser: string;
  memberCode: string;
  userAgent: string;
}>;

export type NseRequestOptions = {
  method: string;
  path: string;
  jsonBody?: unknown;
  headers?: HeadersInit;
  timeoutMs?: number;
  maxResponseBytes?: number;
};

export type NseResponse = {
  status: number;
  headers: Headers;
  body: Uint8Array;
};

export type NseFetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;
