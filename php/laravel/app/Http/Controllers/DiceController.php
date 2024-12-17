<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

class DiceController extends Controller
{
    public function roll()
    {
        $result = random_int(1, 6); // Generates a random number between 1 and 6
        return response()->json([
            'dice_roll' => $result,
            'timestamp' => now()
        ]);
    }
}
