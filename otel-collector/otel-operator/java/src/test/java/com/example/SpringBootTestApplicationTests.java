package com.example;

import com.example.model.User;
import com.example.service.UserService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureWebMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Integration tests for Spring Boot Test Application
 */
@SpringBootTest
@AutoConfigureWebMvc
@ActiveProfiles("test")
class SpringBootTestApplicationTests {

    @Autowired
    private WebApplicationContext webApplicationContext;

    @Autowired
    private UserService userService;

    @Autowired
    private ObjectMapper objectMapper;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext).build();
        // Clear any existing data by reinitializing the service
        userService.initializeSampleData();
    }

    @Test
    void contextLoads() {
        // Test that the application context loads successfully
        assertNotNull(userService);
    }

    @Test
    void testCreateUser() throws Exception {
        User user = new User();
        user.setUsername("testuser");
        user.setEmail("test@example.com");
        user.setFirstName("Test");
        user.setLastName("User");

        mockMvc.perform(post("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(user)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.username").value("testuser"))
                .andExpect(jsonPath("$.email").value("test@example.com"))
                .andExpect(jsonPath("$.firstName").value("Test"))
                .andExpect(jsonPath("$.lastName").value("User"));
    }

    @Test
    void testGetAllUsers() throws Exception {
        mockMvc.perform(get("/api/users"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$[0].username").exists());
    }

    @Test
    void testGetUserById() throws Exception {
        // First create a user
        User user = new User("testuser", "test@example.com", "Test", "User");
        User createdUser = userService.createUser(user);

        mockMvc.perform(get("/api/users/{id}", createdUser.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("testuser"))
                .andExpect(jsonPath("$.email").value("test@example.com"));
    }

    @Test
    void testGetUserByUsername() throws Exception {
        // First create a user
        User user = new User("testuser", "test@example.com", "Test", "User");
        userService.createUser(user);

        mockMvc.perform(get("/api/users/username/{username}", "testuser"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("testuser"))
                .andExpect(jsonPath("$.email").value("test@example.com"));
    }

    @Test
    void testUpdateUser() throws Exception {
        // First create a user
        User user = new User("testuser", "test@example.com", "Test", "User");
        User createdUser = userService.createUser(user);

        User updateData = new User();
        updateData.setUsername("updateduser");
        updateData.setEmail("updated@example.com");
        updateData.setFirstName("Updated");
        updateData.setLastName("User");

        mockMvc.perform(put("/api/users/{id}", createdUser.getId())
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(updateData)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("updateduser"))
                .andExpect(jsonPath("$.email").value("updated@example.com"));
    }

    @Test
    void testDeleteUser() throws Exception {
        // First create a user
        User user = new User("testuser", "test@example.com", "Test", "User");
        User createdUser = userService.createUser(user);

        mockMvc.perform(delete("/api/users/{id}", createdUser.getId()))
                .andExpect(status().isNoContent());
    }

    @Test
    void testSearchUsersByName() throws Exception {
        // Create test users
        userService.createUser(new User("john_doe", "john@example.com", "John", "Doe"));
        userService.createUser(new User("jane_doe", "jane@example.com", "Jane", "Doe"));

        mockMvc.perform(get("/api/users/search")
                .param("name", "Doe"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$[0].lastName").value("Doe"));
    }

    @Test
    void testGetUsersByFirstName() throws Exception {
        // Create test users
        userService.createUser(new User("john_doe", "john@example.com", "John", "Doe"));
        userService.createUser(new User("john_smith", "johnsmith@example.com", "John", "Smith"));

        mockMvc.perform(get("/api/users/firstname/{firstName}", "John"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$[0].firstName").value("John"));
    }

    @Test
    void testHealthEndpoint() throws Exception {
        mockMvc.perform(get("/api/users/health"))
                .andExpect(status().isOk())
                .andExpect(content().string("User service is running!"));
    }

    @Test
    void testInitializeData() throws Exception {
        mockMvc.perform(post("/api/users/init"))
                .andExpect(status().isOk())
                .andExpect(content().string("Sample data initialized successfully!"));
    }

    @Test
    void testValidationError() throws Exception {
        User invalidUser = new User();
        // Missing required fields

        mockMvc.perform(post("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidUser)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testDuplicateUsernameError() throws Exception {
        // Create first user
        User user1 = new User("testuser", "test1@example.com", "Test", "User");
        userService.createUser(user1);

        // Try to create second user with same username
        User user2 = new User();
        user2.setUsername("testuser"); // Same username
        user2.setEmail("test2@example.com");
        user2.setFirstName("Test");
        user2.setLastName("User");

        mockMvc.perform(post("/api/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(user2)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void testUserNotFound() throws Exception {
        mockMvc.perform(get("/api/users/{id}", 999L))
                .andExpect(status().isNotFound());
    }
} 