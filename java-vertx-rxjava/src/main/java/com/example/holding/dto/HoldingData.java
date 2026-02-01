package com.example.holding.dto;

public class HoldingData {
    private String symbol;
    private String tradingType;
    private int quantity;
    private double avgPrice;
    private double currentPrice;
    private double pnl;

    public HoldingData() {}

    public HoldingData(String symbol, String tradingType, int quantity, double avgPrice, double currentPrice, double pnl) {
        this.symbol = symbol;
        this.tradingType = tradingType;
        this.quantity = quantity;
        this.avgPrice = avgPrice;
        this.currentPrice = currentPrice;
        this.pnl = pnl;
    }

    public String getSymbol() { return symbol; }
    public void setSymbol(String symbol) { this.symbol = symbol; }

    public String getTradingType() { return tradingType; }
    public void setTradingType(String tradingType) { this.tradingType = tradingType; }

    public int getQuantity() { return quantity; }
    public void setQuantity(int quantity) { this.quantity = quantity; }

    public double getAvgPrice() { return avgPrice; }
    public void setAvgPrice(double avgPrice) { this.avgPrice = avgPrice; }

    public double getCurrentPrice() { return currentPrice; }
    public void setCurrentPrice(double currentPrice) { this.currentPrice = currentPrice; }

    public double getPnl() { return pnl; }
    public void setPnl(double pnl) { this.pnl = pnl; }
}
