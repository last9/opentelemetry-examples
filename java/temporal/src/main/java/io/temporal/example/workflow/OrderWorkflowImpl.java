package io.temporal.example.workflow;

import io.temporal.activity.ActivityOptions;
import io.temporal.common.RetryOptions;
import io.temporal.example.activity.OrderActivities;
import io.temporal.workflow.Workflow;
import org.slf4j.Logger;

import java.time.Duration;

public class OrderWorkflowImpl implements OrderWorkflow {

    private static final Logger logger = Workflow.getLogger(OrderWorkflowImpl.class);

    private final OrderActivities activities = Workflow.newActivityStub(
            OrderActivities.class,
            ActivityOptions.newBuilder()
                    .setStartToCloseTimeout(Duration.ofSeconds(30))
                    .setRetryOptions(RetryOptions.newBuilder()
                            .setMaximumAttempts(3)
                            .build())
                    .build()
    );

    @Override
    public String processOrder(String orderId, String customerId, double amount) {
        logger.info("Starting order workflow for orderId: {}", orderId);

        // Step 1: Validate order
        boolean isValid = activities.validateOrder(orderId, customerId, amount);
        if (!isValid) {
            logger.warn("Order validation failed for orderId: {}", orderId);
            return "ORDER_VALIDATION_FAILED";
        }

        // Step 2: Reserve inventory
        boolean inventoryReserved = activities.reserveInventory(orderId);
        if (!inventoryReserved) {
            logger.warn("Inventory reservation failed for orderId: {}", orderId);
            return "INVENTORY_RESERVATION_FAILED";
        }

        // Step 3: Process payment
        String paymentId = activities.processPayment(orderId, customerId, amount);
        if (paymentId == null || paymentId.isEmpty()) {
            // Compensate: release inventory
            activities.releaseInventory(orderId);
            logger.warn("Payment processing failed for orderId: {}", orderId);
            return "PAYMENT_FAILED";
        }

        // Step 4: Send confirmation
        activities.sendConfirmation(orderId, customerId, paymentId);

        logger.info("Order workflow completed successfully for orderId: {}", orderId);
        return "ORDER_COMPLETED:" + paymentId;
    }
}
