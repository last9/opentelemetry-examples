import { Controller, Get, Param, Post, Put } from '@nestjs/common';
import { UsersService } from './users.service';

@Controller()
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('/api/users')
  getAllUsers(): string {
    return this.usersService.getAllUsers();
  }

  @Get('/api/users/:id')
  getUserByID(@Param('id') id: string): string {
    return this.usersService.getUserById(id);
  }

  @Post('/api/users/create')
  createUser(): string {
    return this.usersService.createUser();
  }

  @Put('/api/users/update/:id')
  updateUser(@Param('id') id: string): string {
    return this.usersService.updateUser(id);
  }
}
