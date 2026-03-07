package io.temporal.example.activity;

import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

@ActivityInterface
public interface OrderActivities {

    @ActivityMethod
    boolean validateOrder(String orderId, String customerId, double amount);

    @ActivityMethod
    boolean reserveInventory(String orderId);

    @ActivityMethod
    void releaseInventory(String orderId);

    @ActivityMethod
    String processPayment(String orderId, String customerId, double amount);

    @ActivityMethod
    void sendConfirmation(String orderId, String customerId, String paymentId);
}
