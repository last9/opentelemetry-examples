package io.temporal.example.activity;

import io.temporal.activity.Activity;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.UUID;

public class OrderActivitiesImpl implements OrderActivities {

    private static final Logger logger = LoggerFactory.getLogger(OrderActivitiesImpl.class);

    @Override
    public boolean validateOrder(String orderId, String customerId, double amount) {
        logger.info("Validating order: orderId={}, customerId={}, amount={}", orderId, customerId, amount);

        // Simulate validation logic
        simulateWork(100);

        if (amount <= 0) {
            logger.warn("Order validation failed: invalid amount");
            return false;
        }

        if (customerId == null || customerId.isEmpty()) {
            logger.warn("Order validation failed: invalid customer");
            return false;
        }

        logger.info("Order validated successfully: orderId={}", orderId);
        return true;
    }

    @Override
    public boolean reserveInventory(String orderId) {
        logger.info("Reserving inventory for orderId: {}", orderId);

        // Simulate inventory reservation
        simulateWork(150);

        logger.info("Inventory reserved successfully for orderId: {}", orderId);
        return true;
    }

    @Override
    public void releaseInventory(String orderId) {
        logger.info("Releasing inventory for orderId: {}", orderId);

        // Simulate inventory release
        simulateWork(50);

        logger.info("Inventory released for orderId: {}", orderId);
    }

    @Override
    public String processPayment(String orderId, String customerId, double amount) {
        logger.info("Processing payment: orderId={}, customerId={}, amount={}", orderId, customerId, amount);

        // Simulate payment processing
        simulateWork(200);

        String paymentId = "PAY-" + UUID.randomUUID().toString().substring(0, 8);
        logger.info("Payment processed successfully: orderId={}, paymentId={}", orderId, paymentId);
        return paymentId;
    }

    @Override
    public void sendConfirmation(String orderId, String customerId, String paymentId) {
        logger.info("Sending confirmation: orderId={}, customerId={}, paymentId={}", orderId, customerId, paymentId);

        // Simulate sending confirmation
        simulateWork(100);

        logger.info("Confirmation sent for orderId: {}", orderId);
    }

    private void simulateWork(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw Activity.wrap(e);
        }
    }
}
