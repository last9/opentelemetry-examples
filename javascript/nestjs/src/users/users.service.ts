import { Injectable } from '@nestjs/common';

@Injectable()
export class UsersService {
  getAllUsers(): string {
    return 'All users';
  }

  getUserById(id: string): string {
    return `User with id ${id}`;
  }

  createUser(): string {
    return 'User created';
  }

  updateUser(id: string): string {
    return `User with id ${id} updated`;
  }

  deleteUser(id: string): string {
    return `User with id ${id} deleted`;
  }
}
