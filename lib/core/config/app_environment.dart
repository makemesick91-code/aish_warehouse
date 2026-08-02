enum AppEnvironment {
  development,
  staging,
  production,
  test;

  static AppEnvironment parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'development' || 'dev' => AppEnvironment.development,
        'staging' => AppEnvironment.staging,
        'production' || 'prod' => AppEnvironment.production,
        'test' => AppEnvironment.test,
        _ => throw const FormatException('APP_ENV tidak valid.'),
      };
}
