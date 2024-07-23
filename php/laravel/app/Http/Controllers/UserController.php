<?php
namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;

class UserController extends Controller
{
    public function index()
    {
        return "Hello World";
    }

    public function create()
    {
        return "Hello World";
    }

    public function store(Request $request)
    {
        return "Hello World";
    }

    public function show(User $user)
    {
        return "Hello World";
    }

    public function edit(User $user)
    {
        return "Hello World";
    }

    public function update(Request $request, User $user)
    {
        return "Hello World";
    }

    public function destroy(User $user)
    {
        return "Hello World";
    }
}
