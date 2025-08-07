package common

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// RecordExceptionInSpan records detailed exception information in the span
func RecordExceptionInSpan(c *gin.Context, message string, errInput ...interface{}) {
	// Retrieve span from context
	spanValue, exists := c.Get("span")
	if !exists {
		return
	}
	
	span, ok := spanValue.(trace.Span)
	if !ok {
		return
	}
	
	// Create error with message
	err := fmt.Errorf("%s", message)
	
	// Record the error in the span
	span.RecordError(err)
	span.SetStatus(codes.Error, message)
	
	// Add timestamp
	span.SetAttributes(
		attribute.String("exception.timestamp", time.Now().UTC().Format(time.RFC3339)),
		attribute.String("exception.message", message),
	)
	
	// Add custom attributes from errInput
	var attrs []attribute.KeyValue
	for i := 0; i < len(errInput); i += 2 {
		if i+1 < len(errInput) {
			key := fmt.Sprintf("exception.%v", errInput[i])
			value := fmt.Sprintf("%v", errInput[i+1])
			attrs = append(attrs, attribute.String(key, value))
		}
	}
	
	// Add stack trace information
	if len(attrs) > 0 {
		span.SetAttributes(attrs...)
	}
	
	// Add stack trace for debugging (only in development)
	if os.Getenv("APP_ENV") == "development" {
		stackTrace := getStackTrace()
		span.SetAttributes(attribute.String("exception.stack_trace", stackTrace))
	}
}

// RecordExceptionWithStack records exception with full stack trace
func RecordExceptionWithStack(c *gin.Context, err error, additionalInfo ...interface{}) {
	spanValue, exists := c.Get("span")
	if !exists {
		return
	}
	
	span, ok := spanValue.(trace.Span)
	if !ok {
		return
	}
	
	// Record the error
	span.RecordError(err)
	span.SetStatus(codes.Error, err.Error())
	
	// Add basic exception attributes
	span.SetAttributes(
		attribute.String("exception.timestamp", time.Now().UTC().Format(time.RFC3339)),
		attribute.String("exception.type", fmt.Sprintf("%T", err)),
		attribute.String("exception.message", err.Error()),
	)
	
	// Add stack trace
	stackTrace := getStackTrace()
	span.SetAttributes(attribute.String("exception.stack_trace", stackTrace))
	
	// Add additional information
	var attrs []attribute.KeyValue
	for i := 0; i < len(additionalInfo); i += 2 {
		if i+1 < len(additionalInfo) {
			key := fmt.Sprintf("exception.%v", additionalInfo[i])
			value := fmt.Sprintf("%v", additionalInfo[i+1])
			attrs = append(attrs, attribute.String(key, value))
		}
	}
	
	if len(attrs) > 0 {
		span.SetAttributes(attrs...)
	}
}

// getStackTrace returns a formatted stack trace
func getStackTrace() string {
	var stack []string
	for i := 1; i < 10; i++ { // Limit to 10 frames
		pc, file, line, ok := runtime.Caller(i)
		if !ok {
			break
		}
		
		fn := runtime.FuncForPC(pc)
		if fn == nil {
			continue
		}
		
		// Skip internal Go runtime functions
		if strings.Contains(fn.Name(), "runtime.") || 
		   strings.Contains(fn.Name(), "reflect.") ||
		   strings.Contains(fn.Name(), "gin.") {
			continue
		}
		
		stack = append(stack, fmt.Sprintf("%s:%d %s", file, line, fn.Name()))
	}
	
	return strings.Join(stack, "\n")
}