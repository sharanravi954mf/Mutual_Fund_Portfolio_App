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
  bodyText?: string;
  contentType?: string;
  accept?: string;
  headers?: HeadersInit;
  timeoutMs?: number;
  maxResponseBytes?: number;
  acceptHttpErrors?: boolean;
};

export type SafeIntegrationHeaderMetadata = Readonly<{
  content_type?: string;
  user_agent?: string;
  accept?: string;
  x_request_id?: string;
  x_correlation_id?: string;
}>;

export type NseResponse = {
  status: number;
  headers: Headers;
  body: Uint8Array;
  safeHeaderMetadata: SafeIntegrationHeaderMetadata;
};

export type NseFetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;
