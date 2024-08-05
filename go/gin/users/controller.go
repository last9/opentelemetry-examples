package users

type UsersControllers struct {
	users *[]User
}

func NewUsersControllers() *UsersControllers {

	users := []User{
		{ID: 1, Name: "John"},
		{ID: 2, Name: "Doe"},
		{ID: 3, Name: "Jane"},
		{ID: 4, Name: "Smith"},
	}

	return &UsersControllers{
		users: &users,
	}
}

func (u *UsersControllers) GetUsers() *[]User {
	// Return users
	return u.users
}

func (u *UsersControllers) GetUser(id int) *User {
	for _, user := range *u.users {
		if user.ID == id {
			return &user
		}
	}
	return nil
}

func (u *UsersControllers) CreateUser(name string) *User {
	// Get the highest ID from the users
	id := 0

	for _, user := range *u.users {
		if user.ID > id {
			id = user.ID
		}
	}

	user := User{
		ID:   id + 1,
		Name: name,
	}

	*u.users = append(*u.users, user)

	return &user
}

func (u *UsersControllers) UpdateUser(id int, name string) *User {
	for i, user := range *u.users {
		if user.ID == id {
			(*u.users)[i].Name = name
			return &(*u.users)[i]
		}
	}
	return nil
}

func (u *UsersControllers) DeleteUser(id int) {
	for i, user := range *u.users {
		if user.ID == id {
			*u.users = append((*u.users)[:i], (*u.users)[i+1:]...)
			break
		}
	}
}
