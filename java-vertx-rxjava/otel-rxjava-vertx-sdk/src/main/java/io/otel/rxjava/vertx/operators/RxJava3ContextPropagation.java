package io.otel.rxjava.vertx.operators;

import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.reactivex.rxjava3.core.*;
import io.reactivex.rxjava3.functions.Function;
import io.reactivex.rxjava3.plugins.RxJavaPlugins;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Enables automatic OpenTelemetry context propagation for RxJava3.
 *
 * This class hooks into RxJava's plugin system to automatically capture and restore
 * OpenTelemetry context across RxJava operators and schedulers.
 *
 * Call {@link #enable()} once at application startup (handled automatically by OtelSdk).
 */
public class RxJava3ContextPropagation {
    private static final Logger log = LoggerFactory.getLogger(RxJava3ContextPropagation.class);
    private static final AtomicBoolean enabled = new AtomicBoolean(false);

    /**
     * Enable OpenTelemetry context propagation for RxJava3.
     * Safe to call multiple times - will only register hooks once.
     */
    public static void enable() {
        if (enabled.compareAndSet(false, true)) {
            registerHooks();
            log.info("RxJava3 OpenTelemetry context propagation enabled");
        }
    }

    /**
     * Check if context propagation is enabled
     */
    public static boolean isEnabled() {
        return enabled.get();
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    private static void registerHooks() {
        // Hook for Single
        Function existingSingleHook = RxJavaPlugins.getOnSingleAssembly();
        RxJavaPlugins.setOnSingleAssembly(single -> {
            Single result = new ContextPropagationSingle<>(single);
            return existingSingleHook != null ? (Single) existingSingleHook.apply(result) : result;
        });

        // Hook for Maybe
        Function existingMaybeHook = RxJavaPlugins.getOnMaybeAssembly();
        RxJavaPlugins.setOnMaybeAssembly(maybe -> {
            Maybe result = new ContextPropagationMaybe<>(maybe);
            return existingMaybeHook != null ? (Maybe) existingMaybeHook.apply(result) : result;
        });

        // Hook for Completable
        Function existingCompletableHook = RxJavaPlugins.getOnCompletableAssembly();
        RxJavaPlugins.setOnCompletableAssembly(completable -> {
            Completable result = new ContextPropagationCompletable(completable);
            return existingCompletableHook != null ? (Completable) existingCompletableHook.apply(result) : result;
        });

        // Hook for Observable
        Function existingObservableHook = RxJavaPlugins.getOnObservableAssembly();
        RxJavaPlugins.setOnObservableAssembly(observable -> {
            Observable result = new ContextPropagationObservable<>(observable);
            return existingObservableHook != null ? (Observable) existingObservableHook.apply(result) : result;
        });

        // Hook for Flowable
        Function existingFlowableHook = RxJavaPlugins.getOnFlowableAssembly();
        RxJavaPlugins.setOnFlowableAssembly(flowable -> {
            Flowable result = new ContextPropagationFlowable<>(flowable);
            return existingFlowableHook != null ? (Flowable) existingFlowableHook.apply(result) : result;
        });

        // Hook for schedulers - wrap scheduled runnables with context
        RxJavaPlugins.setScheduleHandler(RxJava3ContextPropagation::wrapWithContext);
    }

    /**
     * Wrap a Runnable to preserve OpenTelemetry context
     */
    public static Runnable wrapWithContext(Runnable runnable) {
        Context context = Context.current();
        return () -> {
            try (Scope scope = context.makeCurrent()) {
                runnable.run();
            }
        };
    }

    /**
     * Wrap a callable to preserve OpenTelemetry context
     */
    public static <T> java.util.concurrent.Callable<T> wrapWithContext(java.util.concurrent.Callable<T> callable) {
        Context context = Context.current();
        return () -> {
            try (Scope scope = context.makeCurrent()) {
                return callable.call();
            }
        };
    }

    // ============ Context-propagating RxJava types ============

    private static class ContextPropagationSingle<T> extends Single<T> {
        private final Single<T> source;
        private final Context context;

        ContextPropagationSingle(Single<T> source) {
            this.source = source;
            this.context = Context.current();
        }

        @Override
        protected void subscribeActual(SingleObserver<? super T> observer) {
            try (Scope scope = context.makeCurrent()) {
                source.subscribe(new ContextPropagationSingleObserver<>(observer, context));
            }
        }
    }

    private static class ContextPropagationSingleObserver<T> implements SingleObserver<T> {
        private final SingleObserver<? super T> downstream;
        private final Context context;

        ContextPropagationSingleObserver(SingleObserver<? super T> downstream, Context context) {
            this.downstream = downstream;
            this.context = context;
        }

        @Override
        public void onSubscribe(io.reactivex.rxjava3.disposables.Disposable d) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSubscribe(d);
            }
        }

        @Override
        public void onSuccess(T t) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSuccess(t);
            }
        }

        @Override
        public void onError(Throwable e) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onError(e);
            }
        }
    }

    private static class ContextPropagationMaybe<T> extends Maybe<T> {
        private final Maybe<T> source;
        private final Context context;

        ContextPropagationMaybe(Maybe<T> source) {
            this.source = source;
            this.context = Context.current();
        }

        @Override
        protected void subscribeActual(MaybeObserver<? super T> observer) {
            try (Scope scope = context.makeCurrent()) {
                source.subscribe(new ContextPropagationMaybeObserver<>(observer, context));
            }
        }
    }

    private static class ContextPropagationMaybeObserver<T> implements MaybeObserver<T> {
        private final MaybeObserver<? super T> downstream;
        private final Context context;

        ContextPropagationMaybeObserver(MaybeObserver<? super T> downstream, Context context) {
            this.downstream = downstream;
            this.context = context;
        }

        @Override
        public void onSubscribe(io.reactivex.rxjava3.disposables.Disposable d) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSubscribe(d);
            }
        }

        @Override
        public void onSuccess(T t) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSuccess(t);
            }
        }

        @Override
        public void onError(Throwable e) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onError(e);
            }
        }

        @Override
        public void onComplete() {
            try (Scope scope = context.makeCurrent()) {
                downstream.onComplete();
            }
        }
    }

    private static class ContextPropagationCompletable extends Completable {
        private final Completable source;
        private final Context context;

        ContextPropagationCompletable(Completable source) {
            this.source = source;
            this.context = Context.current();
        }

        @Override
        protected void subscribeActual(CompletableObserver observer) {
            try (Scope scope = context.makeCurrent()) {
                source.subscribe(new ContextPropagationCompletableObserver(observer, context));
            }
        }
    }

    private static class ContextPropagationCompletableObserver implements CompletableObserver {
        private final CompletableObserver downstream;
        private final Context context;

        ContextPropagationCompletableObserver(CompletableObserver downstream, Context context) {
            this.downstream = downstream;
            this.context = context;
        }

        @Override
        public void onSubscribe(io.reactivex.rxjava3.disposables.Disposable d) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSubscribe(d);
            }
        }

        @Override
        public void onComplete() {
            try (Scope scope = context.makeCurrent()) {
                downstream.onComplete();
            }
        }

        @Override
        public void onError(Throwable e) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onError(e);
            }
        }
    }

    private static class ContextPropagationObservable<T> extends Observable<T> {
        private final Observable<T> source;
        private final Context context;

        ContextPropagationObservable(Observable<T> source) {
            this.source = source;
            this.context = Context.current();
        }

        @Override
        protected void subscribeActual(Observer<? super T> observer) {
            try (Scope scope = context.makeCurrent()) {
                source.subscribe(new ContextPropagationObserver<>(observer, context));
            }
        }
    }

    private static class ContextPropagationObserver<T> implements Observer<T> {
        private final Observer<? super T> downstream;
        private final Context context;

        ContextPropagationObserver(Observer<? super T> downstream, Context context) {
            this.downstream = downstream;
            this.context = context;
        }

        @Override
        public void onSubscribe(io.reactivex.rxjava3.disposables.Disposable d) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSubscribe(d);
            }
        }

        @Override
        public void onNext(T t) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onNext(t);
            }
        }

        @Override
        public void onError(Throwable e) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onError(e);
            }
        }

        @Override
        public void onComplete() {
            try (Scope scope = context.makeCurrent()) {
                downstream.onComplete();
            }
        }
    }

    private static class ContextPropagationFlowable<T> extends Flowable<T> {
        private final Flowable<T> source;
        private final Context context;

        ContextPropagationFlowable(Flowable<T> source) {
            this.source = source;
            this.context = Context.current();
        }

        @Override
        protected void subscribeActual(org.reactivestreams.Subscriber<? super T> subscriber) {
            try (Scope scope = context.makeCurrent()) {
                source.subscribe(new ContextPropagationSubscriber<>(subscriber, context));
            }
        }
    }

    private static class ContextPropagationSubscriber<T> implements FlowableSubscriber<T> {
        private final org.reactivestreams.Subscriber<? super T> downstream;
        private final Context context;

        ContextPropagationSubscriber(org.reactivestreams.Subscriber<? super T> downstream, Context context) {
            this.downstream = downstream;
            this.context = context;
        }

        @Override
        public void onSubscribe(org.reactivestreams.Subscription s) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onSubscribe(s);
            }
        }

        @Override
        public void onNext(T t) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onNext(t);
            }
        }

        @Override
        public void onError(Throwable e) {
            try (Scope scope = context.makeCurrent()) {
                downstream.onError(e);
            }
        }

        @Override
        public void onComplete() {
            try (Scope scope = context.makeCurrent()) {
                downstream.onComplete();
            }
        }
    }
}
