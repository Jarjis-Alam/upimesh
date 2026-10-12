package com.demo.upimesh;

import com.demo.upimesh.model.Account;
import com.demo.upimesh.model.AccountRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.List;

@Component
public class DataSeeder implements CommandLineRunner {

    private final AccountRepository accountRepository;

    public DataSeeder(AccountRepository accountRepository) {
        this.accountRepository = accountRepository;
    }

    @Override
    public void run(String... args) {
        if (accountRepository.count() == 0) {
            accountRepository.saveAll(List.of(
                new Account("alice", new BigDecimal("5000.00")),
                new Account("bob", new BigDecimal("1000.00")),
                new Account("carol", new BigDecimal("2000.00"))
            ));
        }
    }
}
