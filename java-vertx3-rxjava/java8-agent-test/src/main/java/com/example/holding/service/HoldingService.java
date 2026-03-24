package com.example.holding.service;

import com.example.holding.model.Holding;
import com.example.holding.repository.HoldingRepository;
import io.reactivex.Completable;
import io.reactivex.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

/**
 * Service layer for Holding operations.
 */
public class HoldingService {

    private static final Logger logger = LoggerFactory.getLogger(HoldingService.class);

    private final HoldingRepository repository;

    public HoldingService(HoldingRepository repository) {
        this.repository = repository;
    }

    public Single<List<Holding>> getAllHoldings() {
        logger.debug("Fetching all holdings");
        return repository.findAll();
    }

    public Single<List<Holding>> getHoldingsByUserId(String userId) {
        logger.debug("Fetching holdings for user: {}", userId);
        return repository.findByUserId(userId);
    }

    public Single<Holding> createHolding(Holding holding) {
        logger.info("Creating holding: {} {} shares for user {}",
                holding.getSymbol(), holding.getQuantity(), holding.getUserId());
        return repository.save(holding);
    }

    public Completable deleteHolding(Long id) {
        logger.info("Deleting holding with id: {}", id);
        return repository.deleteById(id);
    }
}
