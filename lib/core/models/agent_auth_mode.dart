/// How an assistant's ACP agent authenticates its model requests.
enum AgentAuthMode {
  /// Use the provider, API key and model selected in Moru.
  provider,

  /// Use the supported agent's own signed-in account and model defaults.
  subscription,
}
