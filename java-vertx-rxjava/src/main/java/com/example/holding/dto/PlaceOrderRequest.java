package com.example.holding.dto;

public class PlaceOrderRequest {
    private String symbol;
    private String tradingType;
    private int quantity;
    private double price;
    private String orderType;

    public PlaceOrderRequest() {}

    public String getSymbol() { return symbol; }
    public void setSymbol(String symbol) { this.symbol = symbol; }

    public String getTradingType() { return tradingType; }
    public void setTradingType(String tradingType) { this.tradingType = tradingType; }

    public int getQuantity() { return quantity; }
    public void setQuantity(int quantity) { this.quantity = quantity; }

    public double getPrice() { return price; }
    public void setPrice(double price) { this.price = price; }

    public String getOrderType() { return orderType; }
    public void setOrderType(String orderType) { this.orderType = orderType; }
}
