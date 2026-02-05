package com.example.holding.dto;

import java.util.List;

public class GetAllHoldingsResponse {
    private String userId;
    private List<HoldingData> holdings;
    private int totalCount;
    private String message;

    public GetAllHoldingsResponse() {}

    public GetAllHoldingsResponse(String userId, List<HoldingData> holdings, int totalCount, String message) {
        this.userId = userId;
        this.holdings = holdings;
        this.totalCount = totalCount;
        this.message = message;
    }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public List<HoldingData> getHoldings() { return holdings; }
    public void setHoldings(List<HoldingData> holdings) { this.holdings = holdings; }

    public int getTotalCount() { return totalCount; }
    public void setTotalCount(int totalCount) { this.totalCount = totalCount; }

    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }
}
