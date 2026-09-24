```sh
docker compose up -d
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 01_setup_publisher_distributor.sql
sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 02_setup_subscriber_db.sql
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 03_create_subscription.sql
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 04_validate_on_publisher.sql
sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 05_check_subscriber.sql
sqlcmd -S localhost,14330 -U sa -P 'P@ssw0rd_Pub1' -C -i 06_test_edge_cases_on_publisher.sql
sqlcmd -S localhost,14331 -U sa -P 'P@ssw0rd_Sub1' -C -i 07_check_subscriber_after_tests.sql
```
