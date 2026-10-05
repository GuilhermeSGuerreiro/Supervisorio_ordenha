idf_component_register(
  SRCS "main.cpp" "fila.cpp" "rede.cpp" "coleta.cpp" "rtc.cpp" "hx711.cpp"
  INCLUDE_DIRS "."
  PRIV_REQUIRES
    nvs_flash esp_partition esp_wifi esp_netif esp_event esp_http_client
    esp_timer esp_driver_gpio esp_driver_uart esp_driver_i2c esp_http_server json app_update
)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra)
