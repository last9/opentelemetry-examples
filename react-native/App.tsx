import React, { useEffect, useState, useCallback } from "react";
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  SafeAreaView,
  StatusBar,
  ActivityIndicator,
  Platform,
  Modal,
  TextInput,
} from "react-native";
import { NavigationContainer } from "@react-navigation/native";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { WebView } from "react-native-webview";
import type { WebViewMessageEvent } from "react-native-webview";
import {
  L9Rum,
  L9ReactNavigationInstrumentation,
} from "@last9/rum-react-native";
import { RUM_CONFIG } from "./src/rum";

/** JSONPlaceholder mock API — https://jsonplaceholder.typicode.com/guide/ */
const API_BASE = "https://jsonplaceholder.typicode.com";

const PUBLIC_API_DEMOS = [
  {
    label: "todos limit",
    url: `${API_BASE}/todos?_limit=1`,
  },
  {
    label: "comments by post",
    url: `${API_BASE}/comments?postId=1`,
  },
  {
    label: "user detail",
    url: `${API_BASE}/users/1`,
  },
  {
    label: "album detail",
    url: `${API_BASE}/albums/1`,
  },
  {
    label: "GitHub zen",
    url: "https://api.github.com/zen",
  },
  {
    label: "random dog image API",
    url: "https://dog.ceo/api/breeds/image/random",
  },
];

const TRACKED_NETWORK_DEMOS = [
  {
    label: "tracked posts list",
    url: `${API_BASE}/posts?_limit=3`,
  },
  {
    label: "tracked todo detail",
    url: `${API_BASE}/todos/2`,
  },
  {
    label: "tracked GitHub rate limit",
    url: "https://api.github.com/rate_limit",
  },
];

interface Post {
  userId: number;
  id: number;
  title: string;
  body: string;
}

interface Comment {
  postId: number;
  id: number;
  name: string;
  email: string;
  body: string;
}

interface User {
  id: number;
  name: string;
  email: string;
}

interface TimedJsonResult<T> {
  data: T;
  result: ApiResult;
}

interface DemoRequestTags {
  tab: "home" | "network";
  name: string;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Types
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface ApiResult {
  label: string;
  method: string;
  path: string;
  status: number;
  ok: boolean;
  durationMs: number;
  error: string | null;
  body: string | null;
}

interface LogEntry {
  id: number;
  ts: string;
  msg: string;
}

type HomeStackParams = { Dashboard: undefined; Detail: { title: string } };
type RootTabParams = {
  HomeTab: undefined;
  NetworkTab: undefined;
  WebViewTab: undefined;
  ErrorsTab: undefined;
  ProfileTab: undefined;
};

const Tab = createBottomTabNavigator<RootTabParams>();
const HStack = createNativeStackNavigator<HomeStackParams>();

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  API helper — every call goes through fetch so the SDK's network
//  instrumentation can capture it with W3C traceparent headers.
//  Uses JSONPlaceholder (https://jsonplaceholder.typicode.com/guide/)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function demoUrl(url: string, tags: DemoRequestTags): string {
  const taggedUrl = new URL(url);
  taggedUrl.searchParams.set("l9_demo", "true");
  taggedUrl.searchParams.set("l9_demo_tab", tags.tab);
  taggedUrl.searchParams.set("l9_demo_request", tags.name);
  return taggedUrl.toString();
}

function demoHeaders(tags: DemoRequestTags) {
  return {
    "Content-Type": "application/json; charset=UTF-8",
    "X-L9-Demo": "true",
    "X-L9-Demo-Tab": tags.tab,
    "X-L9-Demo-Request": tags.name,
  };
}

async function api(
  method: string,
  path: string,
  body?: object,
  tags: DemoRequestTags = { tab: "network", name: `${method} ${path}` }
): Promise<ApiResult> {
  const url = demoUrl(`${API_BASE}${path}`, tags);
  const start = Date.now();
  try {
    const res = await fetch(url, {
      method,
      headers: demoHeaders(tags),
      body: body ? JSON.stringify(body) : undefined,
    });
    const ms = Date.now() - start;
    const text = await res.text().catch(() => "");
    return {
      label: `${method} ${path}`,
      method,
      path,
      status: res.status,
      ok: res.ok,
      durationMs: ms,
      error: null,
      body: text.slice(0, 500),
    };
  } catch (e: any) {
    const ms = Date.now() - start;
    return {
      label: `${method} ${path}`,
      method,
      path,
      status: 0,
      ok: false,
      durationMs: ms,
      error: e.message,
      body: null,
    };
  }
}

async function timedJson<T>(label: string, url: string, tags: DemoRequestTags): Promise<TimedJsonResult<T>> {
  const requestUrl = demoUrl(url, tags);
  const start = Date.now();
  try {
    const res = await fetch(requestUrl, { headers: demoHeaders(tags) });
    const text = await res.text().catch(() => "");
    const ms = Date.now() - start;
    return {
      data: text ? JSON.parse(text) : null,
      result: {
        label,
        method: "GET",
        path: requestUrl,
        status: res.status,
        ok: res.ok,
        durationMs: ms,
        error: null,
        body: text.slice(0, 500),
      },
    };
  } catch (e: any) {
    const ms = Date.now() - start;
    return {
      data: null as T,
      result: {
        label,
        method: "GET",
        path: requestUrl,
        status: 0,
        ok: false,
        durationMs: ms,
        error: e.message,
        body: null,
      },
    };
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Global event log (shared across screens)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let _logs: LogEntry[] = [];
let _logId = 0;
let _logListeners: Array<(l: LogEntry[]) => void> = [];
function addLog(msg: string) {
  const entry: LogEntry = {
    id: ++_logId,
    ts: new Date().toLocaleTimeString(),
    msg,
  };
  _logs = [entry, ..._logs.slice(0, 99)];
  _logListeners.forEach((fn) => fn(_logs));
}
function useLogs() {
  const [logs, setLogs] = useState<LogEntry[]>(_logs);
  useEffect(() => {
    _logListeners.push(setLogs);
    return () => {
      _logListeners = _logListeners.filter((fn) => fn !== setLogs);
    };
  }, []);
  return logs;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  SDK init must happen at module load — before any React useEffect fires —
//  otherwise child screens' useEffects (which run before the App's) will hit
//  an un-initialized SDK and an un-patched global.fetch.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

L9Rum.initialize(RUM_CONFIG);

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  App entry — NavigationContainer + L9ReactNavigationInstrumentation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export default function App() {
  useEffect(() => {
    addLog("L9Rum.initialize() (called at module load)");
    L9Rum.getSessionId().then((id) =>
      addLog(`sessionId: ${id?.slice(0, 12)}…`)
    );
  }, []);

  return (
    <NavigationContainer
      onStateChange={(state) => {
        // Automatic route tracking — sends startView for every navigation
        L9ReactNavigationInstrumentation.onStateChange(state);
        const name = getRouteName(state);
        if (name) addLog(`route → ${name}`);
      }}
    >
      <SafeAreaView style={s.safe}>
        <StatusBar barStyle="dark-content" backgroundColor="#fff" />
        <Tab.Navigator
          screenOptions={{
            headerShown: false,
            tabBarActiveTintColor: ACCENT,
            tabBarInactiveTintColor: "#999",
            tabBarStyle: { borderTopWidth: 1, borderTopColor: "#eee" },
          }}
        >
          <Tab.Screen
            name="HomeTab"
            component={HomeNav}
            options={{ tabBarLabel: "Home", tabBarIcon: () => <Text>🏠</Text> }}
          />
          <Tab.Screen
            name="NetworkTab"
            component={NetworkScreen}
            options={{
              tabBarLabel: "Network",
              tabBarIcon: () => <Text>🌐</Text>,
            }}
          />
          <Tab.Screen
            name="WebViewTab"
            component={WebViewCorrelationScreen}
            options={{
              tabBarLabel: "WebView",
              tabBarIcon: () => <Text>🔗</Text>,
            }}
          />
          <Tab.Screen
            name="ErrorsTab"
            component={ErrorsScreen}
            options={{
              tabBarLabel: "Errors",
              tabBarIcon: () => <Text>⚠️</Text>,
            }}
          />
          <Tab.Screen
            name="ProfileTab"
            component={ProfileScreen}
            options={{
              tabBarLabel: "Profile",
              tabBarIcon: () => <Text>👤</Text>,
            }}
          />
        </Tab.Navigator>
      </SafeAreaView>
    </NavigationContainer>
  );
}

function getRouteName(state: any): string | null {
  if (!state?.routes?.length) return null;
  const r = state.routes[state.index ?? state.routes.length - 1];
  if (r?.state) return getRouteName(r.state);
  return r?.name ?? null;
}

// The Last9 dashboard is a CSR React SPA — window.L9RUM persists across
// in-app route changes (no full document reloads), and its origin
// (https://app.last9.io) is already in the dev clientToken's whitelist
// (RUM_CONFIG.clientToken JWT properties.origins), so the WebView's
// Browser RUM exports won't 403. No local dev server or adb reverse
// plumbing required — just open the WebView tab and the page loads.
const WEBVIEW_TEST_URL = "https://app.last9.io/";
const BROWSER_RUM_SDK_URL = "https://cdn.last9.io/rum-sdk/builds/2.5.0-alpha/l9.umd.js";

const WEBVIEW_RUM_BOOTSTRAP = `
  (function() {
    if (window.__L9_WEBVIEW_RUM_BOOTSTRAPPED) return true;
    window.__L9_WEBVIEW_RUM_BOOTSTRAPPED = true;

    function postContext(reason) {
      try {
        window.ReactNativeWebView && window.ReactNativeWebView.postMessage(JSON.stringify({
          reason: reason,
          href: window.location.href,
          hasL9RUM: !!window.L9RUM,
          context: window.__LAST9_RUM_NATIVE_CONTEXT || null
        }));
      } catch (_) {}
    }

    function initBrowserRum() {
      if (!window.L9RUM || !window.__LAST9_RUM_NATIVE_CONTEXT) {
        setTimeout(initBrowserRum, 100);
        return;
      }

      try {
        window.L9RUM.init({
          baseUrl: ${JSON.stringify(RUM_CONFIG.baseUrl)},
          headers: { clientToken: ${JSON.stringify(RUM_CONFIG.clientToken)} },
          resourceAttributes: {
            serviceName: ${JSON.stringify(RUM_CONFIG.serviceName)},
            deploymentEnvironment: ${JSON.stringify(RUM_CONFIG.deploymentEnvironment)},
            appVersion: ${JSON.stringify(RUM_CONFIG.serviceVersion)}
          },
          sampleRate: 100,
          debug: true,
          debugLogs: true
        });

        window.L9RUM.addEvent('webview_real_page_loaded', {
          source: 'react-native-webview-demo'
        });
        postContext('browser-rum-init');
      } catch (e) {
        postContext('browser-rum-init-error:' + (e && e.message ? e.message : e));
      }
    }

    function loadBrowserRum() {
      if (window.L9RUM) {
        initBrowserRum();
        return;
      }

      var script = document.createElement('script');
      script.src = ${JSON.stringify(BROWSER_RUM_SDK_URL)};
      script.async = true;
      script.onload = initBrowserRum;
      script.onerror = function () { postContext('browser-rum-load-error'); };
      (document.head || document.documentElement).appendChild(script);
    }

    window.addEventListener('l9rum:native_context', function () {
      postContext('l9rum:native_context');
    });

    loadBrowserRum();
    setTimeout(function () { postContext('initial-page-load'); }, 500);
  })();
  true;
`;

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Home Tab — Stack with Dashboard + Detail
//  Features: App startup, View transitions, Network requests
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function HomeNav() {
  return (
    <HStack.Navigator screenOptions={{ headerShown: false }}>
      <HStack.Screen name="Dashboard" component={DashboardScreen} />
      <HStack.Screen name="Detail" component={DetailScreen} />
    </HStack.Navigator>
  );
}

function DashboardScreen({ navigation }: any) {
  const [posts, setPosts] = useState<Post[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [comments, setComments] = useState<Comment[]>([]);
  const [homeRequests, setHomeRequests] = useState<ApiResult[]>([]);
  const [loading, setLoading] = useState(true);

  const loadHomeData = useCallback(async () => {
    setLoading(true);
    L9Rum.startView("Home");
    addLog("startView: Home");
    try {
      const [postsRes, usersRes, commentsRes, delayOneRes, delayThreeRes] = await Promise.all([
        timedJson<Post[]>("Home fast posts", `${API_BASE}/posts?_limit=20`, { tab: "home", name: "posts-list" }),
        timedJson<User[]>("Home fast users", `${API_BASE}/users?_limit=5`, { tab: "home", name: "users-list" }),
        timedJson<Comment[]>("Home fast comments", `${API_BASE}/comments?postId=1`, { tab: "home", name: "comments-for-post" }),
        timedJson<object>("Home delayed 1s", "https://httpbin.org/delay/1", { tab: "home", name: "delay-1s" }),
        timedJson<object>("Home delayed 3s", "https://httpbin.org/delay/3", { tab: "home", name: "delay-3s" }),
      ]);
      const requestResults = [
        postsRes.result,
        usersRes.result,
        commentsRes.result,
        delayOneRes.result,
        delayThreeRes.result,
      ];
      const maxResult = requestResults.reduce((max, result) =>
        result.durationMs > max.durationMs ? result : max
      );
      setPosts(postsRes.data ?? []);
      setUsers(usersRes.data ?? []);
      setComments(commentsRes.data ?? []);
      setHomeRequests(requestResults);
      addLog(`Home APIs complete; expected max view.ttfd source: ${maxResult.label} (${maxResult.durationMs}ms)`);
    } catch (e: any) {
      addLog(`Home APIs failed: ${e.message}`);
    }
    setLoading(false);
  }, []);

  useEffect(() => { loadHomeData(); }, [loadHomeData]);

  return (
    <View style={s.screen}>
      <View style={s.header}>
        <Text style={s.headerTitle}>Posts</Text>
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {loading ? (
          <View style={s.loadingCard}>
            <ActivityIndicator style={{ padding: 20 }} />
            <Text style={s.hint}>
              Loading posts, users, and comments before the Home screen is fully displayed.
            </Text>
          </View>
        ) : (
          <>
            <FeatureBadge
              features={[
                "Home starts an active View before API requests",
                "Fast and delayed GET requests run before full content render",
                "SDK sets view.ttfd from the maximum request time on this view",
                "Home APIs include l9_demo_tab=home query tags",
              ]}
            />
            <View style={s.summaryCard}>
              <Text style={s.summaryTitle}>Home full display data</Text>
              <Text style={s.summaryText}>{posts.length} posts</Text>
              <Text style={s.summaryText}>{users.length} users</Text>
              <Text style={s.summaryText}>{comments.length} comments for the featured post</Text>
            </View>
            <Text style={s.sectionTitle}>TTFD Request Timings</Text>
              <Text style={s.hint}>
              The delayed 3s request should usually be the max-duration source for view.ttfd.
              Filter dashboard URLs by l9_demo_tab=home or l9_demo_request=delay-3s.
            </Text>
            {homeRequests.map((result) => (
              <ApiCard key={result.label} result={result} />
            ))}
            <View style={{ gap: 8 }}>
              {posts.map((post) => (
                <TouchableOpacity
                  key={post.id}
                  style={s.listItem}
                  onPress={() => {
                    L9Rum.addEvent("nav_tap", { destination: `Post #${post.id}` });
                    addLog(`nav → Post #${post.id}`);
                    navigation.navigate("Detail", { postId: post.id });
                  }}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={s.listText} numberOfLines={1}>{post.title}</Text>
                    <Text style={s.listSub} numberOfLines={1}>{post.body}</Text>
                  </View>
                  <Text style={s.listChevron}>›</Text>
                </TouchableOpacity>
              ))}
            </View>
            <Text style={s.sectionTitle}>Featured Users</Text>
            {users.map((user) => (
              <View key={user.id} style={[s.apiCard, { borderLeftColor: ACCENT }]}>
                <Text style={s.apiLabel}>{user.name}</Text>
                <Text style={s.listSub}>{user.email}</Text>
              </View>
            ))}
            <Text style={s.sectionTitle}>Featured Comments</Text>
            {comments.slice(0, 3).map((comment) => (
              <View key={comment.id} style={[s.apiCard, { borderLeftColor: "#00B894" }]}>
                <Text style={s.apiLabel}>{comment.name}</Text>
                <Text style={s.apiBody} numberOfLines={2}>{comment.body}</Text>
              </View>
            ))}
          </>
        )}
      </ScrollView>
    </View>
  );
}

function DetailScreen({ route, navigation }: any) {
  const postId: number = route.params?.postId ?? 1;
  const [post, setPost] = useState<Post | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const postTags: DemoRequestTags = { tab: "home", name: "detail-post" };
      const commentsTags: DemoRequestTags = { tab: "home", name: "detail-comments" };
      const postUrl = demoUrl(`${API_BASE}/posts/${postId}`, postTags);
      const commentsUrl = demoUrl(`${API_BASE}/posts/${postId}/comments`, commentsTags);
      const [postRes, commentsRes] = await Promise.all([
        fetch(postUrl, { headers: demoHeaders(postTags) }),
        fetch(commentsUrl, { headers: demoHeaders(commentsTags) }),
      ]);
      const postData: Post = await postRes.json();
      const commentsData: Comment[] = await commentsRes.json();
      setPost(postData);
      setComments(commentsData);
      setLoading(false);
      addLog(`GET /posts/${postId} → ${postRes.status}`);
      addLog(`GET /posts/${postId}/comments → ${commentsRes.status} (${commentsData.length})`);
    })();
  }, [postId]);

  return (
    <View style={s.screen}>
      <View style={s.header}>
        <TouchableOpacity onPress={() => navigation.goBack()}>
          <Text style={s.backText}>← Back</Text>
        </TouchableOpacity>
        <Text style={s.headerTitle}>Post #{postId}</Text>
        <View style={{ width: 50 }} />
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {loading ? (
          <ActivityIndicator style={{ padding: 20 }} />
        ) : (
          <>
            <Text style={s.sectionTitle}>{post?.title}</Text>
            <Text style={[s.hint, { marginBottom: 16 }]}>{post?.body}</Text>
            <Text style={s.sectionTitle}>Comments ({comments.length})</Text>
            {comments.map((c) => (
              <View key={c.id} style={[s.apiCard, { borderLeftColor: ACCENT }]}>
                <Text style={s.apiLabel}>{c.name}</Text>
                <Text style={s.listSub}>{c.email}</Text>
                <Text style={s.apiBody}>{c.body}</Text>
              </View>
            ))}
          </>
        )}
      </ScrollView>
    </View>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Network Tab
//  Features: Network instrumentation, W3C trace context, Baggage, Backend correlation
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

interface Todo {
  userId: number;
  id: number;
  title: string;
  completed: boolean;
}

function NetworkScreen() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [loading, setLoading] = useState(true);
  const [publicApiLoading, setPublicApiLoading] = useState(false);
  const [trackedLoading, setTrackedLoading] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [results, setResults] = useState<ApiResult[]>([]);

  const loadTodos = useCallback(async () => {
    setLoading(true);
    const r = await api("GET", "/todos?_limit=10", undefined, { tab: "network", name: "todos-list" });
    try { setTodos(JSON.parse(r.body ?? "[]")); } catch { setTodos([]); }
    setResults((prev) => [r, ...prev]);
    addLog(`GET /todos → ${r.status} (${r.durationMs}ms)`);
    setLoading(false);
  }, []);

  useEffect(() => { loadTodos(); }, [loadTodos]);

  const createTodo = async () => {
    if (!newTitle.trim()) return;
    const r = await api("POST", "/todos", {
      title: newTitle.trim(),
      completed: false,
      userId: 1,
    }, { tab: "network", name: "todo-create" });
    setResults((prev) => [r, ...prev]);
    addLog(`POST /todos → ${r.status} (${r.durationMs}ms)`);
    try {
      const created: Todo = JSON.parse(r.body ?? "{}");
      setTodos((prev) => [created, ...prev]);
    } catch {}
    setNewTitle("");
  };

  const toggleTodo = async (todo: Todo) => {
    const r = await api("PATCH", `/todos/${todo.id}`, {
      completed: !todo.completed,
    }, { tab: "network", name: "todo-toggle" });
    setResults((prev) => [r, ...prev]);
    addLog(`PATCH /todos/${todo.id} → ${r.status} (${r.durationMs}ms)`);
    setTodos((prev) =>
      prev.map((t) => (t.id === todo.id ? { ...t, completed: !t.completed } : t))
    );
  };

  const deleteTodo = async (id: number) => {
    const r = await api("DELETE", `/todos/${id}`, undefined, { tab: "network", name: "todo-delete" });
    setResults((prev) => [r, ...prev]);
    addLog(`DELETE /todos/${id} → ${r.status} (${r.durationMs}ms)`);
    setTodos((prev) => prev.filter((t) => t.id !== id));
  };

  const runPublicApiDemos = async () => {
    setPublicApiLoading(true);
    const publicApiResults = await Promise.all(
      PUBLIC_API_DEMOS.map(async ({ label, url }) => {
        const tags: DemoRequestTags = { tab: "network", name: `public-${label.replace(/\s+/g, "-").toLowerCase()}` };
        const requestUrl = demoUrl(url, tags);
        const start = Date.now();
        try {
          const res = await fetch(requestUrl, { headers: demoHeaders(tags) });
          const durationMs = Date.now() - start;
          return {
            label: `PUBLIC API ${label}`,
            method: "GET",
            path: requestUrl,
            status: res.status,
            ok: res.ok,
            durationMs,
            error: null,
            body: "Tracked by RUM network instrumentation and should appear in the Last9 dashboard.",
          };
        } catch (e: any) {
          const durationMs = Date.now() - start;
          return {
            label: `PUBLIC API ${label}`,
            method: "GET",
            path: requestUrl,
            status: 0,
            ok: false,
            durationMs,
            error: e.message,
            body: null,
          };
        }
      })
    );
    setResults((prev) => [...publicApiResults, ...prev]);
    addLog(`public API demo → ${publicApiResults.length} captured requests`);
    setPublicApiLoading(false);
  };

  const runTrackedNetworkDemos = async () => {
    setTrackedLoading(true);
    const trackedResults = await Promise.all(
      TRACKED_NETWORK_DEMOS.map(async ({ label, url }) => {
        const tags: DemoRequestTags = { tab: "network", name: label.replace(/\s+/g, "-").toLowerCase() };
        const requestUrl = demoUrl(url, tags);
        const start = Date.now();
        try {
          const res = await fetch(requestUrl, { headers: demoHeaders(tags) });
          const text = await res.text().catch(() => "");
          const durationMs = Date.now() - start;
          return {
            label: `TRACKED ${label}`,
            method: "GET",
            path: requestUrl,
            status: res.status,
            ok: res.ok,
            durationMs,
            error: null,
            body: text.slice(0, 500),
          };
        } catch (e: any) {
          const durationMs = Date.now() - start;
          return {
            label: `TRACKED ${label}`,
            method: "GET",
            path: requestUrl,
            status: 0,
            ok: false,
            durationMs,
            error: e.message,
            body: null,
          };
        }
      })
    );
    setResults((prev) => [...trackedResults, ...prev]);
    addLog(`tracked demo → ${trackedResults.length} captured requests`);
    setTrackedLoading(false);
  };

  return (
    <View style={s.screen}>
      <View style={s.header}>
        <Text style={s.headerTitle}>Todos</Text>
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <FeatureBadge
          features={[
            "GET /todos (list)",
            "POST /todos (create)",
            "PATCH /todos/:id (toggle)",
            "DELETE /todos/:id (remove)",
            "public API demos visible in the dashboard",
            "ignorePatterns only suppress image/CDN resources",
            "Network APIs include l9_demo_tab=network query tags",
          ]}
        />

        {/* Add todo */}
        <View style={[s.row, { marginBottom: 12, alignItems: "center" }]}>
          <View style={{ flex: 1, marginRight: 8, borderWidth: 1, borderColor: "#ddd", borderRadius: 8, paddingHorizontal: 12, backgroundColor: "#fff" }}>
            <TextInput
              style={{ fontSize: 14, color: "#333", paddingVertical: 10 }}
              placeholder="New todo..."
              placeholderTextColor="#999"
              value={newTitle}
              onChangeText={setNewTitle}
              onSubmitEditing={createTodo}
              returnKeyType="done"
            />
          </View>
          <TouchableOpacity style={s.primaryBtn} onPress={createTodo}>
            <Text style={s.primaryBtnText}>Add</Text>
          </TouchableOpacity>
        </View>

        {/* Todo list */}
        {loading ? (
          <ActivityIndicator style={{ padding: 20 }} />
        ) : (
          <View style={{ gap: 6 }}>
            {todos.map((todo) => (
              <View key={todo.id} style={[s.listItem, { alignItems: "center" }]}>
                <TouchableOpacity
                  onPress={() => toggleTodo(todo)}
                  style={{ marginRight: 10 }}
                >
                  <Text style={{ fontSize: 18 }}>
                    {todo.completed ? "✅" : "⬜"}
                  </Text>
                </TouchableOpacity>
                <Text
                  style={[
                    s.listText,
                    { flex: 1 },
                    todo.completed && { textDecorationLine: "line-through", color: "#999" },
                  ]}
                  numberOfLines={2}
                >
                  {todo.title}
                </Text>
                <TouchableOpacity onPress={() => deleteTodo(todo.id)}>
                  <Text style={{ fontSize: 16, color: "#FF6B6B" }}>✕</Text>
                </TouchableOpacity>
              </View>
            ))}
          </View>
        )}

        <Text style={s.sectionTitle}>Public API Requests</Text>
        <Text style={s.hint}>
          Sends public API requests across JSONPlaceholder, GitHub, and dog.ceo.
          These no longer match ignorePatterns, so they should create network
          spans and appear in the Last9 dashboard. Image/CDN patterns are still
          ignored to avoid noisy resource spans. Filter by l9_demo_tab=network.
        </Text>
        <TouchableOpacity
          style={s.primaryBtn}
          onPress={runPublicApiDemos}
          disabled={publicApiLoading}
        >
          <Text style={s.primaryBtnText}>
            {publicApiLoading ? "Sending public API requests..." : "Run Public API Demo"}
          </Text>
        </TouchableOpacity>

        <Text style={s.sectionTitle}>Tracked Network Requests</Text>
        <Text style={s.hint}>
          Sends requests that do not match ignorePatterns, so these should
          create network spans and appear in the Last9 dashboard. Filter by
          l9_demo_tab=network or l9_demo_request.
        </Text>
        <TouchableOpacity
          style={s.primaryBtn}
          onPress={runTrackedNetworkDemos}
          disabled={trackedLoading}
        >
          <Text style={s.primaryBtnText}>
            {trackedLoading ? "Sending tracked requests..." : "Run Tracked Requests Demo"}
          </Text>
        </TouchableOpacity>

        {/* API log */}
        {results.length > 0 && (
          <>
            <Text style={[s.sectionTitle, { marginTop: 16 }]}>API Log</Text>
            {results.slice(0, 10).map((r, i) => (
              <ApiCard key={`${r.label}-${i}`} result={r} />
            ))}
          </>
        )}
      </ScrollView>
    </View>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  WebView Tab
//  Features: Native session/view correlation for Browser RUM in WebViews
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function WebViewCorrelationScreen() {
  const [injectedJavaScript, setInjectedJavaScript] = useState<string | null>(null);
  const [nativeContext, setNativeContext] = useState<string>("Waiting for WebView context...");
  const [nativeSessionId, setNativeSessionId] = useState<string | null>(null);
  const [nativeViewId, setNativeViewId] = useState<string | null>(null);
  const [webViewKey, setWebViewKey] = useState(0);

  const loadInjectedJavaScript = useCallback(async () => {
    try {
      L9Rum.startView("WebViewSessionCorrelation");
      const script = await L9Rum.getWebViewInjectedJavaScript();
      setInjectedJavaScript(`${script}\n${WEBVIEW_RUM_BOOTSTRAP}`);
      addLog(`WebView injected JS loaded (${script.length} chars)`);
    } catch (e: any) {
      setNativeContext(`Failed to load WebView injected JavaScript: ${e.message}`);
      L9Rum.captureError(e, { screen: "WebViewCorrelation" });
    }
  }, []);

  useEffect(() => {
    loadInjectedJavaScript();
  }, [loadInjectedJavaScript]);

  const handleMessage = (event: WebViewMessageEvent) => {
    try {
      const payload = JSON.parse(event.nativeEvent.data);
      const context = payload.context ?? {};
      const sessionId = context.sessionId ?? null;
      const viewId = context.nativeViewId ?? context.viewId ?? null;
      setNativeSessionId(sessionId);
      setNativeViewId(viewId);
      setNativeContext(JSON.stringify(payload, null, 2));
      addLog(`WebView context → session:${sessionId ?? "missing"} view:${viewId ?? "missing"}`);
    } catch (e: any) {
      setNativeContext(event.nativeEvent.data);
    }
  };

  const refreshWebViewContext = async () => {
    await loadInjectedJavaScript();
    setWebViewKey((key) => key + 1);
  };

  return (
    <View style={s.screen}>
      <View style={s.header}>
        <Text style={s.headerTitle}>WebView Correlation</Text>
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <FeatureBadge
          features={[
            "getWebViewInjectedJavaScript() native context helper",
            "Loads a public WebView site that makes API requests",
            "Native session.id shared with Browser RUM in the page",
            "Native view.id stamped as native.view.id",
          ]}
        />
        <Text style={s.hint}>
          This screen loads Hacker News Search in a real WebView. That page
          makes public Algolia API requests, while the app injects native
          context and boots Browser RUM on the page.
        </Text>

        <TouchableOpacity style={s.primaryBtn} onPress={refreshWebViewContext}>
          <Text style={s.primaryBtnText}>Refresh WebView Context</Text>
        </TouchableOpacity>

        <Text style={s.sectionTitle}>Last Context Probe</Text>
        <View style={s.summaryCard}>
          <Text style={s.summaryTitle}>Native WebView Context</Text>
          <Text style={s.summaryText} selectable>
            sessionId: {nativeSessionId ?? "waiting..."}
          </Text>
          <Text style={s.summaryText} selectable>
            native.view.id: {nativeViewId ?? "waiting..."}
          </Text>
        </View>
        <View style={s.contextCard}>
          <Text style={s.contextText} selectable>
            {nativeContext}
          </Text>
        </View>

        <Text style={s.sectionTitle}>Actual WebView</Text>
        <View style={s.webViewCard}>
          {injectedJavaScript ? (
            <WebView
              key={webViewKey}
              source={{ uri: WEBVIEW_TEST_URL }}
              injectedJavaScriptBeforeContentLoaded={injectedJavaScript}
              injectedJavaScript={injectedJavaScript}
              onMessage={handleMessage}
              javaScriptEnabled
              domStorageEnabled
              sharedCookiesEnabled
              thirdPartyCookiesEnabled
              startInLoadingState
              style={s.webView}
            />
          ) : (
            <ActivityIndicator style={{ padding: 40 }} />
          )}
        </View>

      </ScrollView>
    </View>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Errors Tab
//  Features: Error tracking, Exception capture, ANR, Promise rejections, Stack traces
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function ErrorsScreen() {
  return (
    <View style={s.screen}>
      <View style={s.header}>
        <Text style={s.headerTitle}>Errors</Text>
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <FeatureBadge
          features={[
            "Manual Error Capture (captureError)",
            "Unhandled JS Exception (errorInstrumentation)",
            "Promise Rejection Tracking",
            "ANR Detection (Android, 5s threshold)",
            "Stack Traces with Context",
          ]}
        />
        <Text style={s.hint}>
          errorInstrumentation: true auto-captures unhandled JS errors.
          anrDetectionEnabled: true watches for main-thread blocks {">"}5s
          (Android only).
        </Text>

        <ErrorButton
          title="Capture Error (with context)"
          subtitle="L9Rum.captureError(err, { screen, severity, user_action })"
          color="#FF6B6B"
          onPress={() => {
            const err = new Error("Checkout failed: payment gateway timeout");
            L9Rum.captureError(err, {
              screen: "Checkout",
              severity: "high",
              user_action: "submit_payment",
              cart_total: 149.99,
            });
            addLog("captureError: payment gateway timeout");
          }}
        />

        <ErrorButton
          title="Capture TypeError"
          subtitle="Simulates accessing property of undefined"
          color="#FF9F43"
          onPress={() => {
            try {
              const obj: any = undefined;
              obj.foo.bar;
            } catch (e) {
              L9Rum.captureError(e, {
                screen: "ErrorsDemo",
                type: "TypeError",
              });
              addLog("captureError: TypeError");
            }
          }}
        />

        <ErrorButton
          title="Capture Network Error"
          subtitle="Simulates a failed API call error"
          color="#EE5A24"
          onPress={() => {
            L9Rum.captureError(
              new Error("NetworkError: Failed to fetch /todos"),
              {
                screen: "Todos",
                endpoint: "/todos",
                http_method: "GET",
                retry_count: 3,
              }
            );
            addLog("captureError: NetworkError");
          }}
        />

        <ErrorButton
          title="Unhandled Promise Rejection"
          subtitle="Throws inside an async function (auto-captured)"
          color="#6C5CE7"
          onPress={() => {
            Promise.reject(
              new Error("Unhandled: session token expired")
            ).catch(() => {
              /* swallow for demo safety */
            });
            // Also capture it explicitly so it shows up
            L9Rum.captureError(
              new Error("Unhandled: session token expired"),
              { source: "promise_rejection" }
            );
            addLog("captureError: promise rejection");
          }}
        />

        <ErrorButton
          title="Capture Error with Stack Trace"
          subtitle="Deep call stack to demonstrate trace capture"
          color="#A29BFE"
          onPress={() => {
            function level3() {
              throw new Error("Deep stack: database connection pool exhausted");
            }
            function level2() {
              level3();
            }
            function level1() {
              level2();
            }
            try {
              level1();
            } catch (e) {
              L9Rum.captureError(e, {
                screen: "ErrorsDemo",
                stack_depth: 3,
              });
              addLog("captureError: deep stack trace");
            }
          }}
        />

        <ErrorButton
          title="ANR Simulation (Android only)"
          subtitle="Blocks JS thread for ~3s — ANR watchdog may fire if >5s"
          color="#FD79A8"
          onPress={() => {
            addLog("starting ANR simulation (3s block)…");
            const end = Date.now() + 3000;
            while (Date.now() < end) {
              /* busy-wait to block JS thread */
            }
            addLog("ANR simulation complete");
          }}
        />

        <ErrorButton
          title="Fire Multiple Errors (Burst)"
          subtitle="5 rapid errors to test batching & export"
          color="#00B894"
          onPress={() => {
            for (let i = 1; i <= 5; i++) {
              L9Rum.captureError(new Error(`Burst error #${i}`), {
                index: i,
                screen: "ErrorsDemo",
              });
            }
            addLog("captureError: 5 burst errors");
          }}
        />
      </ScrollView>
    </View>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Profile Tab
//  Features: User identification, Session management, Span attributes, Custom events
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function ProfileScreen() {
  const [loggedIn, setLoggedIn] = useState(false);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [debugVisible, setDebugVisible] = useState(false);
  const logs = useLogs();

  useEffect(() => {
    L9Rum.getSessionId().then(setSessionId);
  }, []);

  return (
    <View style={s.screen}>
      <View style={s.header}>
        <Text style={s.headerTitle}>Profile</Text>
        <TouchableOpacity onPress={() => setDebugVisible(true)}>
          <Text style={{ fontSize: 18 }}>📋</Text>
        </TouchableOpacity>
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <FeatureBadge
          features={[
            "User Identification (identify / clearUser)",
            "Session Tracking (4h max / 30min inactivity)",
            "Head-based Sampling (sampleRate)",
            "Global Span Attributes",
            "Custom Events (addEvent)",
            "Resource Monitoring (CPU/memory)",
            "Flush Control",
          ]}
        />

        {/* User card */}
        <View style={s.profileCard}>
          <View style={s.avatar}>
            <Text style={s.avatarText}>{loggedIn ? "PW" : "?"}</Text>
          </View>
          <Text style={s.profileName}>
            {loggedIn ? "Piyush Pawar" : "Guest User"}
          </Text>
          <Text style={s.profileEmail}>
            {loggedIn ? "piyush@last9.io" : "Not signed in"}
          </Text>
          {loggedIn ? (
            <TouchableOpacity
              style={s.outlineBtn}
              onPress={() => {
                L9Rum.clearUser();
                setLoggedIn(false);
                addLog("clearUser()");
              }}
            >
              <Text style={s.outlineBtnText}>Sign Out</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity
              style={s.primaryBtn}
              onPress={() => {
                L9Rum.identify({
                  id: "piyush-01",
                  name: "Piyush",
                  email: "piyush@last9.io",
                  fullName: "Piyush Pawar",
                  roles: ["developer", "admin"],
                });
                setLoggedIn(true);
                addLog("identify: Piyush Pawar (piyush-01)");
              }}
            >
              <Text style={s.primaryBtnText}>Sign In</Text>
            </TouchableOpacity>
          )}
        </View>
        <Text style={s.hint}>
          identify() sets user.id, user.name, user.email, user.full_name,
          user.roles as span attributes on all subsequent spans.
        </Text>

        {/* Span Attributes */}
        <Text style={s.sectionTitle}>Global Span Attributes</Text>
        <Text style={s.hint}>
          spanAttributes() adds key-value pairs to every span. Useful for
          A/B test variants, feature flags, etc.
        </Text>
        <View style={s.row}>
          <TouchableOpacity
            style={[s.actionBtn, { flex: 1, marginRight: 6 }]}
            onPress={() => {
              L9Rum.spanAttributes({
                "app.experiment": "checkout_v2",
                "app.feature_flag": "new_cart_enabled",
                "app.build_type": "debug",
              });
              addLog("spanAttributes: experiment=checkout_v2");
            }}
          >
            <Text style={s.actionIcon}>🏷️</Text>
            <Text style={s.actionText}>Set Attrs</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[s.actionBtn, { flex: 1, marginLeft: 6 }]}
            onPress={() => {
              L9Rum.spanAttributes(null);
              addLog("spanAttributes: cleared");
            }}
          >
            <Text style={s.actionIcon}>🗑️</Text>
            <Text style={s.actionText}>Clear Attrs</Text>
          </TouchableOpacity>
        </View>

        {/* Custom Events */}
        <Text style={s.sectionTitle}>Custom Events</Text>
        <Text style={s.hint}>
          addEvent() creates a span event with custom attributes.
        </Text>
        <View style={s.row}>
          <TouchableOpacity
            style={[s.actionBtn, { flex: 1, marginRight: 6 }]}
            onPress={() => {
              L9Rum.addEvent("button_click", {
                button: "purchase",
                screen: "Profile",
                value: 99.99,
              });
              addLog("event: button_click (purchase)");
            }}
          >
            <Text style={s.actionIcon}>👆</Text>
            <Text style={s.actionText}>Button Click</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[s.actionBtn, { flex: 1, marginLeft: 6 }]}
            onPress={() => {
              L9Rum.addEvent("feature_used", {
                feature: "dark_mode",
                enabled: true,
                platform: Platform.OS,
              });
              addLog("event: feature_used (dark_mode)");
            }}
          >
            <Text style={s.actionIcon}>⚡</Text>
            <Text style={s.actionText}>Feature Used</Text>
          </TouchableOpacity>
        </View>

        {/* View / Flush */}
        <Text style={s.sectionTitle}>View & Export Control</Text>
        <View style={s.row}>
          <TouchableOpacity
            style={[s.actionBtn, { flex: 1, marginRight: 6 }]}
            onPress={() => {
              L9Rum.setViewName("CustomViewName");
              addLog("setViewName: CustomViewName");
            }}
          >
            <Text style={s.actionIcon}>📱</Text>
            <Text style={s.actionText}>Set View Name</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[s.actionBtn, { flex: 1, marginLeft: 6 }]}
            onPress={() => {
              L9Rum.flush();
              addLog("flush() — exported pending spans");
            }}
          >
            <Text style={s.actionIcon}>📤</Text>
            <Text style={s.actionText}>Flush</Text>
          </TouchableOpacity>
        </View>

        {/* Session info */}
        <Text style={s.sectionTitle}>Session Info</Text>
        <View style={s.sessionCard}>
          <Text style={s.sessionLabel}>Session ID</Text>
          <Text style={s.sessionValue} selectable>
            {sessionId ?? "loading…"}
          </Text>
          <Text style={s.sessionHint}>
            Sessions visible at: RUM → Sessions in the Last9 dashboard.{"\n"}
            Session timeout: 4h max / 30min inactivity.
          </Text>
        </View>

        {/* SDK Config summary */}
        <Text style={s.sectionTitle}>Active SDK Config</Text>
        <View style={s.configCard}>
          {[
            ["serviceName", RUM_CONFIG.serviceName],
            ["serviceVersion", RUM_CONFIG.serviceVersion],
            ["appBuildId", RUM_CONFIG.appBuildId],
            ["environment", RUM_CONFIG.deploymentEnvironment],
            ["sampleRate", `${RUM_CONFIG.sampleRate}%`],
            ["networkInstrumentation", `${RUM_CONFIG.networkInstrumentation}`],
            ["propagationMode", `${RUM_CONFIG.propagationMode}`],
            ["errorInstrumentation", `${RUM_CONFIG.errorInstrumentation}`],
            ["resourceMonitoring", `${RUM_CONFIG.resourceMonitoringEnabled}`],
            ["anrDetection", `${RUM_CONFIG.anrDetectionEnabled}`],
            ["baggage", `${RUM_CONFIG.baggage?.enabled}`],
            [
              "isolateTracePerRequest",
              `${RUM_CONFIG.isolateTracePerRequest}`,
            ],
          ].map(([k, v]) => (
            <View key={k} style={s.configRow}>
              <Text style={s.configKey}>{k}</Text>
              <Text style={s.configVal}>{v}</Text>
            </View>
          ))}
        </View>

      </ScrollView>

      {/* Debug log modal */}
      <Modal visible={debugVisible} animationType="slide" transparent>
        <View style={s.debugOverlay}>
          <View style={s.debugPanel}>
            <View style={s.debugHeader}>
              <Text style={s.debugTitle}>Event Log</Text>
              <TouchableOpacity onPress={() => setDebugVisible(false)}>
                <Text style={s.debugClose}>✕</Text>
              </TouchableOpacity>
            </View>
            <ScrollView style={s.debugLog}>
              {logs.map((e) => (
                <Text key={e.id} style={s.debugLogEntry}>
                  <Text style={s.debugLogTs}>{e.ts} </Text>
                  {e.msg}
                </Text>
              ))}
              {logs.length === 0 && (
                <Text style={s.hint}>No events yet</Text>
              )}
            </ScrollView>
          </View>
        </View>
      </Modal>
    </View>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Shared components
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function FeatureBadge({ features }: { features: string[] }) {
  return (
    <View style={s.featureCard}>
      <Text style={s.featureTitle}>RUM Features on this screen</Text>
      {features.map((f) => (
        <Text key={f} style={s.featureItem}>
          ✓ {f}
        </Text>
      ))}
    </View>
  );
}

function ApiCard({ result }: { result: ApiResult | null }) {
  if (!result) return null;
  const color = result.ok ? "#00B894" : result.status === 0 ? "#636E72" : "#FF6B6B";
  return (
    <View style={[s.apiCard, { borderLeftColor: color }]}>
      <View style={s.apiHeader}>
        <Text style={s.apiLabel}>{result.label}</Text>
        <Text style={[s.apiStatus, { color }]}>
          {result.status || "ERR"} · {result.durationMs}ms
        </Text>
      </View>
      {result.error && <Text style={s.apiError}>{result.error}</Text>}
      {result.body && (
        <Text style={s.apiBody} numberOfLines={3}>
          {result.body}
        </Text>
      )}
    </View>
  );
}

function ErrorButton({
  title,
  subtitle,
  color,
  onPress,
}: {
  title: string;
  subtitle: string;
  color: string;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity
      style={[s.errorBtn, { borderLeftColor: color }]}
      onPress={onPress}
    >
      <Text style={s.errorBtnTitle}>{title}</Text>
      <Text style={s.errorBtnSub}>{subtitle}</Text>
    </TouchableOpacity>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Styles
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const ACCENT = "#6C63FF";

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#fff" },
  screen: { flex: 1, backgroundColor: "#f8f9fa" },

  // Header
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: "#fff",
    borderBottomWidth: 1,
    borderBottomColor: "#eee",
  },
  headerTitle: { fontSize: 18, fontWeight: "700", color: "#111" },
  backText: { fontSize: 14, color: ACCENT, fontWeight: "600" },

  // Section
  sectionTitle: {
    fontSize: 15,
    fontWeight: "700",
    color: "#111",
    marginTop: 20,
    marginBottom: 8,
  },
  hint: { fontSize: 12, color: "#888", lineHeight: 18, marginBottom: 12 },
  row: { flexDirection: "row", marginBottom: 12 },

  // Feature badge
  featureCard: {
    backgroundColor: "#F0EFFF",
    borderRadius: 12,
    padding: 14,
    marginBottom: 16,
  },
  featureTitle: {
    fontSize: 11,
    fontWeight: "700",
    color: ACCENT,
    textTransform: "uppercase",
    letterSpacing: 0.5,
    marginBottom: 6,
  },
  featureItem: { fontSize: 12, color: "#444", lineHeight: 20 },

  loadingCard: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 16,
    alignItems: "center",
    borderWidth: 1,
    borderColor: "#eee",
  },
  summaryCard: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: "#eee",
  },
  summaryTitle: { fontSize: 13, fontWeight: "700", color: "#111", marginBottom: 6 },
  summaryText: { fontSize: 12, color: "#555", lineHeight: 20 },

  // Session
  sessionCard: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: "#eee",
  },
  sessionLabel: {
    fontSize: 11,
    fontWeight: "600",
    color: ACCENT,
    marginBottom: 4,
  },
  sessionValue: { fontSize: 11, fontFamily: "monospace", color: "#333" },
  sessionHint: { fontSize: 10, color: "#aaa", marginTop: 6 },

  // List item
  listItem: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#eee",
  },
  listIcon: { fontSize: 20, marginRight: 12 },
  listText: { flex: 1, fontSize: 14, fontWeight: "600", color: "#111" },
  listSub: { fontSize: 11, color: "#888", marginTop: 2 },
  listChevron: { fontSize: 20, color: "#ccc" },

  // API card
  apiCard: {
    backgroundColor: "#fff",
    borderRadius: 8,
    padding: 12,
    marginBottom: 8,
    borderLeftWidth: 3,
    borderWidth: 1,
    borderColor: "#eee",
  },
  apiHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  apiLabel: { fontSize: 13, fontWeight: "600", color: "#111" },
  apiStatus: { fontSize: 12, fontWeight: "700" },
  apiError: { fontSize: 11, color: "#FF6B6B", marginTop: 4 },
  apiBody: {
    fontSize: 10,
    color: "#888",
    fontFamily: "monospace",
    marginTop: 6,
  },

  // WebView correlation
  contextCard: {
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 12,
    borderWidth: 1,
    borderColor: "#eee",
  },
  contextText: {
    fontSize: 11,
    color: "#333",
    fontFamily: "monospace",
    lineHeight: 16,
  },
  webViewCard: {
    height: 360,
    backgroundColor: "#fff",
    borderRadius: 12,
    overflow: "hidden",
    borderWidth: 1,
    borderColor: "#eee",
    marginBottom: 24,
  },
  webView: { flex: 1, backgroundColor: "#fff" },

  // Buttons
  primaryBtn: {
    backgroundColor: ACCENT,
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: "center",
    marginTop: 12,
  },
  primaryBtnText: { color: "#fff", fontSize: 14, fontWeight: "700" },
  outlineBtn: {
    borderWidth: 1,
    borderColor: "#ddd",
    borderRadius: 20,
    paddingHorizontal: 24,
    paddingVertical: 8,
  },
  outlineBtnText: { fontSize: 13, fontWeight: "600", color: "#555" },
  actionBtn: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    alignItems: "center",
    borderWidth: 1,
    borderColor: "#eee",
  },
  actionIcon: { fontSize: 22, marginBottom: 4 },
  actionText: { fontSize: 12, fontWeight: "500", color: "#555" },

  // Method badge
  methodBadge: {
    backgroundColor: "#E8F5E9",
    borderRadius: 6,
    paddingHorizontal: 8,
    paddingVertical: 2,
  },
  methodText: { fontSize: 10, fontWeight: "700", color: "#43A047" },

  // Error button
  errorBtn: {
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 14,
    marginBottom: 10,
    borderLeftWidth: 4,
    borderWidth: 1,
    borderColor: "#eee",
  },
  errorBtnTitle: { fontSize: 14, fontWeight: "600", color: "#111" },
  errorBtnSub: { fontSize: 11, color: "#888", marginTop: 4 },

  // Profile
  profileCard: {
    backgroundColor: "#fff",
    borderRadius: 16,
    padding: 24,
    alignItems: "center",
    marginBottom: 8,
  },
  avatar: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: ACCENT,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 10,
  },
  avatarText: { color: "#fff", fontSize: 22, fontWeight: "700" },
  profileName: {
    fontSize: 18,
    fontWeight: "700",
    color: "#111",
    marginBottom: 2,
  },
  profileEmail: { fontSize: 13, color: "#888", marginBottom: 14 },

  // Config card
  configCard: {
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 12,
    marginBottom: 24,
    borderWidth: 1,
    borderColor: "#eee",
  },
  configRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    paddingVertical: 5,
    borderBottomWidth: 1,
    borderBottomColor: "#f5f5f5",
  },
  configKey: { fontSize: 12, color: "#888" },
  configVal: { fontSize: 12, fontWeight: "600", color: "#333" },

  // Debug modal
  debugOverlay: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "flex-end",
  },
  debugPanel: {
    backgroundColor: "#fff",
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    padding: 20,
    maxHeight: "65%",
  },
  debugHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 12,
  },
  debugTitle: { fontSize: 16, fontWeight: "700" },
  debugClose: { fontSize: 20, color: "#999" },
  debugLog: { flex: 1, backgroundColor: "#f5f5f5", borderRadius: 8, padding: 8 },
  debugLogEntry: { fontSize: 11, paddingVertical: 1 },
  debugLogTs: { color: "#999" },
});
