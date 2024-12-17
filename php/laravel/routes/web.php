<?php

use Illuminate\Support\Facades\Route;

use App\Http\Controllers\DiceController;

Route::get('/roll-dice', [DiceController::class, 'roll']);

Route::get('/', function () {
    return view('welcome');
});
